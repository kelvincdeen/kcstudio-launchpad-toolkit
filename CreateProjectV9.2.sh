#!/bin/bash

# === ADVANCED PROJECT ARCHITECT v9.2 ===
# Secure, Modular, and Evolvable Full-Stack Project Builder
#

set -euo pipefail
IFS=$'\n\t'

# --- Global Variables & Rollback Tracking ---
PROJECT_ROOT="/var/www"
API_PORT_START=8100
CREATED_DIRS=()
CREATED_USERS=()
CREATED_SERVICES=()
CREATED_NGINX_CONFS=()
CREATED_NGINX_LINKS=()
CREATED_LOGROTATE_CONF=""
PROJECT_CONF_FILE=""

# --- Helper Functions ---
log() { echo -e "\n[+] $1"; }
log_ok() { echo -e "  \e[32m✔\e[0m $1"; }
log_warn() { echo -e "  \e[33m!\e[0m $1"; }
log_err() { echo -e "\n[!] \e[31m$1\e[0m" >&2; }
err() { log_err "$1"; exit 1; }

# --- Cleanup Function ---
cleanup() {
  trap - ERR EXIT
  echo ""
  log_err "An error occurred or script exited unexpectedly. Rolling back all changes..."

  if [ -n "$CREATED_LOGROTATE_CONF" ] && [ -f "$CREATED_LOGROTATE_CONF" ]; then
    log "Removing logrotate config: $CREATED_LOGROTATE_CONF"
    sudo rm -f "$CREATED_LOGROTATE_CONF"
  fi
  if [ ${#CREATED_SERVICES[@]} -gt 0 ]; then
    for service in "${CREATED_SERVICES[@]}"; do
      log "Disabling and stopping service: $service"
      sudo systemctl disable --now "$service" &>/dev/null || true
      sudo rm -f "/etc/systemd/system/$service"
    done
    sudo systemctl daemon-reload
  fi
  if [ ${#CREATED_NGINX_LINKS[@]} -gt 0 ]; then
    for link in "${CREATED_NGINX_LINKS[@]}"; do
      log "Removing NGINX symlink: $link"
      sudo rm -f "$link"
    done
  fi
  if [ ${#CREATED_NGINX_CONFS[@]} -gt 0 ]; then
    for conf in "${CREATED_NGINX_CONFS[@]}"; do
      log "Removing NGINX config: $conf"
      sudo rm -f "$conf"
    done
    (sudo nginx -t && sudo systemctl reload nginx) &>/dev/null || true
  fi
  if [ -n "$PROJECT_CONF_FILE" ] && [ -f "$PROJECT_CONF_FILE" ]; then
      log "Deleting project manifest: $PROJECT_CONF_FILE"
      sudo rm -f "$PROJECT_CONF_FILE"
  fi
  if [ ${#CREATED_USERS[@]} -gt 0 ]; then
    for user in "${CREATED_USERS[@]}"; do
      log "Deleting user: $user"
      sudo userdel -r "$user" &>/dev/null || true
    done
  fi
  if [ ${#CREATED_DIRS[@]} -gt 0 ]; then
    IFS=$'\n' sorted_dirs=($(sort -r <<<"${CREATED_DIRS[*]}")); unset IFS
    for dir in "${sorted_dirs[@]}"; do
      if [ -d "$dir" ]; then
        log "Deleting directory: $dir"
        sudo rm -rf "$dir"
      fi
    done
  fi
  log_ok "Rollback complete. System should be clean."
}

# --- Python Code Generation Functions ---
generate_python_helpers() {
    local path=$1
    sudo tee "$path/helpers.py" > /dev/null << 'PYTHON'
import os
import logging
import sqlite3
import time
import random
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict

import jwt
from fastapi import Depends, HTTPException, Request, Header, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials, APIKeyHeader
from slowapi import Limiter
from slowapi.util import get_remote_address

JWT_SECRET = os.getenv("JWT_SECRET", "default-secret-key")
ALGORITHM = "HS256"
ADMIN_API_KEY = os.getenv("ADMIN_API_KEY")
DB_PATH = os.getenv("DB_PATH", "data.db")

admin_key_scheme = APIKeyHeader(
    name="X-Admin-API-Key",
    scheme_name="AdminKey",
    description="Admin access key required for interal or server-to-server requests.",
    auto_error=False  # disable auto error so you can return your own message
)

reusable_oauth2 = HTTPBearer()
limiter = Limiter(key_func=get_remote_address, default_limits=["100/minute"])

# --- JWT ---
def create_jwt(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(hours=24))
    to_encode.update({"exp": expire, "iat": datetime.now(timezone.utc)})
    return jwt.encode(to_encode, JWT_SECRET, algorithm=ALGORITHM)

def decode_jwt(token: str) -> Optional[Dict[str, any]]:
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[ALGORITHM])
    except jwt.PyJWTError:
        return None

# --- Auth Classes ---
class AuthInfo:
    def __init__(self, user_id: str, email: str):
        self.user_id = user_id
        self.email = email

async def get_current_user(token: HTTPAuthorizationCredentials = Depends(reusable_oauth2)) -> AuthInfo:
    payload = decode_jwt(token.credentials)
    if payload is None:
        raise HTTPException(status_code=403, detail="Invalid or expired token")
    user_id = payload.get("sub")
    email = payload.get("email")
    if user_id is None or email is None:
        raise HTTPException(status_code=403, detail="Invalid token payload")
    return AuthInfo(user_id=user_id, email=email)

async def get_admin_access(x_admin_api_key: str = Security(admin_key_scheme)):
    if not x_admin_api_key or x_admin_api_key != ADMIN_API_KEY:
        raise HTTPException(status_code=403, detail="Forbidden: Invalid Admin API Key")
    return True

# --- Logging ---
def setup_logger(name: str, log_path: str):
    logger = logging.getLogger(name)
    if logger.hasHandlers():
        return logger
    logger.setLevel(logging.INFO)
    log_path_obj = logging.FileHandler(log_path)
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    log_path_obj.setFormatter(formatter)
    logger.addHandler(log_path_obj)
    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(formatter)
    logger.addHandler(stream_handler)
    return logger

# --- SQLite WAL Mode and Retry ---
def get_db():
    db = sqlite3.connect(DB_PATH, check_same_thread=False)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL;")
    try:
        yield db
    finally:
        db.close()

def safe_write(db, query: str, params=(), retries=3):
    for attempt in range(retries):
        try:
            return db.execute(query, params)
        except sqlite3.OperationalError as e:
            if "locked" in str(e).lower() and attempt < retries - 1:
                time.sleep(random.uniform(0.2, 0.5))
            else:
                raise

# --- Real Client IP, works with and without Cloudflare ---
def get_client_ip(request: Request) -> str:
    return request.headers.get("cf-connecting-ip") or request.headers.get("x-real-ip") or request.client.host

PYTHON
}

generate_auth_py() {
    local path=$1
    sudo tee "$path/main.py" >/dev/null << 'PYTHON'
import os
import sqlite3
import uuid
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional
from dotenv import load_dotenv

import resend
from fastapi import FastAPI, Request, HTTPException, BackgroundTasks, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, EmailStr, Field

from helpers import create_jwt, setup_logger, limiter, get_current_user, AuthInfo, get_db, safe_write

load_dotenv()
app = FastAPI(root_path="/v1/auth")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allows all origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.state.limiter = limiter
logger = setup_logger("auth", f"../logs/auth/output.log")
resend.api_key = os.getenv("RESEND_API_KEY")
FRONTEND_DOMAIN = os.getenv("FRONTEND_DOMAIN")
DB_PATH = Path("users.db")

def init_db():
    with sqlite3.connect(DB_PATH) as db:
        db.execute("PRAGMA journal_mode=WAL;")
        db.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            email TEXT UNIQUE NOT NULL,
            display_name TEXT,
            profile_photo TEXT,
            bio TEXT,
            social TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """)
        db.execute("""
        CREATE TABLE IF NOT EXISTS login_tokens (
            token TEXT PRIMARY KEY,
            email TEXT NOT NULL,
            expires_at DATETIME NOT NULL
        );
        """)
        db.execute("CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);")
        db.execute("CREATE INDEX IF NOT EXISTS idx_login_tokens_email ON login_tokens(email);")
        logger.info("Auth database initialized with users and login_tokens tables.")
init_db()

# --- MODELS ---

class LoginRequest(BaseModel):
    email: EmailStr

class VerifyRequest(BaseModel):
    token: str

class UserProfile(BaseModel):
    id: str
    email: EmailStr
    display_name: Optional[str] = None
    profile_photo: Optional[str] = None
    bio: Optional[str] = None
    social: Optional[dict] = None

class ProfileUpdate(BaseModel):
    display_name: Optional[str] = Field(None, min_length=3, max_length=50)
    profile_photo: Optional[str] = None
    bio: Optional[str] = None
    social: Optional[dict] = None

# --- SEND EMAIL ---

def send_login_email(email: str, token: str):
    if not resend.api_key:
        logger.error("Resend API key is not configured. Cannot send email.")
        return
    try:
        # use this if you want to use your own frontend domain-> verify_url = f"https://{FRONTEND_DOMAIN}/verify-login?token={token}"
        verify_url = f"https://launchpad.kcstudio.nl/verify-login?token={token}"

        # load from external template
        template_path = Path(__file__).parent / "email_template.html"
        with open(template_path, "r") as f:
            html = f.read()

        # replace placeholders
        html = html.format(
            verify_url=verify_url,
            frontend=os.getenv("FRONTEND_DOMAIN", "PROJECT_NAME")
        )

        params = {
            "from": f"Login <{os.getenv('RESEND_FROM_EMAIL')}>",
            "to": [email],
            "subject": "Your Magic Link to Log In",
            "html": html,
        }
        resend.Emails.send(params)
        logger.info(f"Magic link sent to {email}.")
    except Exception as e:
        logger.error(f"Failed to send email to {email}: {e}")

# --- ROUTES ---

@app.get("/health")
def health():
    return {"status": "auth is healthy"}

@app.post("/login")
@limiter.limit("5/minute")
async def login(request: Request, body: LoginRequest, background_tasks: BackgroundTasks, db: sqlite3.Connection = Depends(get_db)):
    token, expires = str(uuid.uuid4()), datetime.now(timezone.utc) + timedelta(minutes=15)
    safe_write(db, "INSERT INTO login_tokens (token, email, expires_at) VALUES (?, ?, ?)",
                   (token, body.email.lower(), expires.isoformat()))
    db.commit()
    
    background_tasks.add_task(send_login_email, body.email.lower(), token)
    return {"message": "Magic link sent to your email."}

@app.post("/verify")
@limiter.limit("10/minute")

async def verify(request: Request, body: VerifyRequest, db: sqlite3.Connection = Depends(get_db)):
    db.row_factory = sqlite3.Row
    result = db.execute("SELECT email, expires_at FROM login_tokens WHERE token = ?", (body.token,)).fetchone()
    if not result:
        raise HTTPException(status_code=404, detail="Token not found or already used.")
    email = result['email']
    if datetime.now(timezone.utc) > datetime.fromisoformat(result['expires_at']):
        safe_write(db, "DELETE FROM login_tokens WHERE token = ?", (body.token,))
        db.commit()
        raise HTTPException(status_code=400, detail="Token has expired.")
    safe_write(db, "DELETE FROM login_tokens WHERE token = ?", (body.token,))

    user = db.execute("SELECT * FROM users WHERE email = ?", (email,)).fetchone()
    if not user:
        new_user_id = str(uuid.uuid4())
        safe_write(db,
            "INSERT INTO users (id, email, display_name) VALUES (?, ?, ?)",
            (new_user_id, email, email.split('@')[0])
        )
        user_id = new_user_id
        logger.info(f"New user created: {email} with ID {user_id}")
    else:
        user_id = user['id']
    db.commit()

    jwt_payload = {"sub": user_id, "email": email}
    session_jwt = create_jwt(jwt_payload)
    return {"access_token": session_jwt, "token_type": "bearer"}

@app.get("/me", response_model=UserProfile)
async def get_me(request: Request, current_user: AuthInfo = Depends(get_current_user), db: sqlite3.Connection = Depends(get_db)):
    db.row_factory = sqlite3.Row
    user = db.execute("SELECT * FROM users WHERE id = ?", (current_user.user_id,)).fetchone()
    if not user:
        raise HTTPException(status_code=404, detail="User not found.")
    user_dict = dict(user)
    if user_dict.get("social"):
        user_dict["social"] = json.loads(user_dict["social"])
    return user_dict

@app.put("/me", response_model=UserProfile)
async def update_me(
    request: Request,
    update_data: ProfileUpdate,
    current_user: AuthInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    update_fields = update_data.dict(exclude_unset=True)
    if not update_fields:
        raise HTTPException(status_code=400, detail="No update data provided.")
    
    set_clauses = []
    params = []
    
    for key, value in update_fields.items():
        set_clauses.append(f"{key} = ?")
        # Serialize dict to JSON string for the 'social' field
        if key == "social" and isinstance(value, dict):
            params.append(json.dumps(value))
        else:
            params.append(value)

    params.append(current_user.user_id)
    
    sql_query = f"UPDATE users SET {', '.join(set_clauses)} WHERE id = ?"

    db.row_factory = sqlite3.Row
    safe_write(db, sql_query, tuple(params))
    db.commit()

    user = db.execute("SELECT * FROM users WHERE id = ?", (current_user.user_id,)).fetchone()
    if not user:
        logger.warning(f"User with ID {current_user.user_id} was not found after update. Possible race condition or data inconsistency.")
        raise HTTPException(status_code=404, detail="User not found after update.")
            
    user_dict = dict(user)
    if user_dict.get("social"):
        user_dict["social"] = json.loads(user_dict["social"])
    logger.info(f"User profile updated for {current_user.email} with fields: {list(update_fields.keys())}")
    return user_dict

@app.get("/public-profile/{user_id}")
@limiter.limit("30/minute")
async def public_profile(request: Request, user_id: str, db: sqlite3.Connection = Depends(get_db)):
    db.row_factory = sqlite3.Row
    user = db.execute(
        "SELECT display_name, profile_photo, bio, social FROM users WHERE id = ?",
        (user_id,)
    ).fetchone()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    user_dict = dict(user)
    if user_dict.get("social"):
        user_dict["social"] = json.loads(user_dict["social"])
    return {
        "display_name": user_dict["display_name"],
        "profile_photo": user_dict["profile_photo"],
        "bio": user_dict["bio"],
        "social": user_dict["social"]
    }

@app.delete("/delete-me", status_code=200)
@limiter.limit("5/minute")
async def delete_me(request: Request, current_user: AuthInfo = Depends(get_current_user), db: sqlite3.Connection = Depends(get_db)):
    safe_write(db, "DELETE FROM users WHERE id = ?", (current_user.user_id,))
    safe_write(db, "DELETE FROM login_tokens WHERE email = ?", (current_user.email,))
    db.commit()
    logger.info(f"User {current_user.email} deleted their profile.")
    return { "message": "Your profile has been deleted." }
    

PYTHON

    sudo tee "$path/email_template.html" >/dev/null << 'EMAIL'
<!DOCTYPE html>
<html>
  <body style="margin:0; padding:0; background-color:#ffffff; font-family:Verdana; color:#000000; text-align:center;">
    <div style="max-width:600px; margin:0 auto; padding:40px;">
      
      <h1 style="margin-bottom:10px; font-size:28px; font-weight:bold;">KCstudio Launchpad</h1>
      <h2 style="margin-top:0; font-size:16px; font-weight:normal;">Fullstack Toolkit for Your VPS</h2>
      <p style="margin:30px 0 20px 0; font-size:16px;">
        Please click the button below to log in to <strong>{frontend}</strong>
      </p>
      <a href="{verify_url}"
         style="display:inline-block; padding:15px 30px; background-color:#000000; color:#ffffff; text-decoration:none; border-radius:5px; font-size:16px;">
         <strong>Log In</strong>
      </a>
      <p style="margin-top:15px; font-size:12px; color:#888888;">
        This link is only valid for 15 minutes.<br><br>
        You can also copy and paste this link into another device to log in.
      </p>
      <div style="margin-top:40px; font-size:12px; color:#888888;">
        This backend magic link login system was created with KCstudio Launchpad Toolkit.<br><br>
        🐙 <a href="https://github.com/kcstudio-launchpad-toolkit" style="color:#888888; text-decoration:none;">GitHub</a>
        &nbsp;|&nbsp;
        🚀 <a href="https://launchpad.kcstudio.nl/backend-tester" style="color:#888888; text-decoration:none;">KCstudio.nl</a>
      </div>
    </div>
  </body>
</html>


EMAIL

}

generate_app_py() {
    local path=$1
    sudo tee "$path/main.py" >/dev/null << 'PYTHON'
import os
from dotenv import load_dotenv
from fastapi import FastAPI, Depends, Request
from fastapi.middleware.cors import CORSMiddleware

from helpers import get_current_user, get_admin_access, setup_logger, limiter, AuthInfo, get_client_ip

load_dotenv()
app = FastAPI(root_path="/v1/app")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.state.limiter = limiter
logger = setup_logger("app", f"../logs/app/output.log")

@app.get("/health")
def health(): return {"status": "app is healthy"}

@app.get("/public-info")
@limiter.limit("20/minute")
def get_public_info(request: Request):
    logger.info(f"Public info requested by {get_client_ip(request)}")
    return {"message": "This is a public endpoint, anyone can see this."}

@app.get("/user/secret-data")
@limiter.limit("20/minute")
async def read_user_secret_data(request: Request, current_user: AuthInfo = Depends(get_current_user)):
    logger.info(f"User-specific secret data requested for user_id {current_user.user_id}")
    return {"user_id": current_user.user_id, "email": current_user.email, "secret": "The secret ingredient is friendship."}

@app.get("/admin/system-status")
@limiter.limit("5/minute")
async def read_admin_dashboard(request: Request, _=Depends(get_admin_access)):
    logger.warning(f"Admin system status accessed by {get_client_ip(request)}")
    return {"message": "Welcome, Admin! System status: All systems nominal."}
PYTHON
}

generate_database_py() {
    local path=$1
    sudo tee "$path/main.py" >/dev/null << 'PYTHON'
import os
import sqlite3
import json
from pathlib import Path
from typing import List, Optional
from datetime import datetime
from dotenv import load_dotenv

from fastapi import FastAPI, Depends, HTTPException, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from helpers import get_current_user, get_admin_access, setup_logger, limiter, AuthInfo, get_db, safe_write

load_dotenv()
app = FastAPI(root_path="/v1/database")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.state.limiter = limiter
logger = setup_logger("database", f"../logs/database/output.log")
DB_PATH = Path("data.db")

def init_db():
    with sqlite3.connect(DB_PATH) as db:
        db.execute("PRAGMA journal_mode=WAL;")
        db.execute("""
        CREATE TABLE IF NOT EXISTS items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            owner_id TEXT NOT NULL,
            slug TEXT UNIQUE NOT NULL,
            title TEXT,
            type TEXT,
            category TEXT,
            tags TEXT,
            status TEXT DEFAULT 'draft',
            data TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """)
        logger.info("Database initialized with flexible JSON hybrid schema.")
        db.execute("CREATE INDEX IF NOT EXISTS idx_items_owner_id ON items(owner_id);")
        db.execute("CREATE INDEX IF NOT EXISTS idx_items_status ON items(status);")
        db.execute("CREATE INDEX IF NOT EXISTS idx_items_type ON items(type);")
        db.execute("CREATE INDEX IF NOT EXISTS idx_items_category ON items(category);")
        db.execute("CREATE INDEX IF NOT EXISTS idx_items_created_at ON items(created_at);")
        logger.info("Database indexes created.")
init_db()

# --- Models ---

class Item(BaseModel):
    id: Optional[int]
    owner_id: str
    slug: str
    title: Optional[str]
    type: Optional[str]
    category: Optional[str]
    tags: Optional[List[str]] = []
    status: Optional[str] = "draft"
    data: Optional[dict] = {}
    created_at: Optional[str]
    updated_at: Optional[str]

class ItemCreate(BaseModel):
    slug: str = Field(..., min_length=3)
    title: Optional[str]
    type: Optional[str]
    category: Optional[str]
    tags: Optional[List[str]] = []
    status: Optional[str] = "draft"
    data: Optional[dict] = {}

class ItemUpdate(BaseModel):
    title: Optional[str]
    type: Optional[str]
    category: Optional[str]
    tags: Optional[List[str]] = []
    status: Optional[str] = "draft"
    data: Optional[dict] = {}

# --- Endpoints ---

@app.get("/health")
def health():
    return {"status": "database is healthy"}

@app.get("/listall", response_model=List[Item])
@limiter.limit("30/minute")
def list_entries(
    request: Request,
    db: sqlite3.Connection = Depends(get_db),
    _ = Depends(get_admin_access),
    status: Optional[str] = None,
    type: Optional[str] = None,
    category: Optional[str] = None,
    owner: Optional[str] = None,
    created_from: Optional[str] = Query(None, description="YYYY-MM-DD"),
    created_to: Optional[str] = Query(None, description="YYYY-MM-DD"),
):
    sql = "SELECT * FROM items WHERE 1=1"
    params = []
    if status:
        sql += " AND status = ?"
        params.append(status)
    if type:
        sql += " AND type = ?"
        params.append(type)
    if category:
        sql += " AND category = ?"
        params.append(category)
    if owner:
        sql += " AND owner_id = ?"
        params.append(owner)
    if created_from:
        sql += " AND created_at >= ?"
        params.append(created_from)
    if created_to:
        sql += " AND created_at <= ?"
        params.append(created_to)
    sql += " ORDER BY created_at DESC"

    rows = db.execute(sql, params).fetchall()
    result = []
    for row in rows:
        item = dict(row)
        item["tags"] = json.loads(item["tags"]) if item["tags"] else []
        item["data"] = json.loads(item["data"]) if item["data"] else {}
        result.append(item)
    return result

@app.get("/listuser", response_model=List[Item])
@limiter.limit("30/minute")
def list_user_entries(
    request: Request,
    current_user: AuthInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db),
):
    rows = db.execute(
        "SELECT * FROM items WHERE owner_id = ? ORDER BY created_at DESC",
        (current_user.user_id,)
    ).fetchall()

    result = []
    for row in rows:
        item = dict(row)
        item["tags"] = json.loads(item["tags"]) if item["tags"] else []
        item["data"] = json.loads(item["data"]) if item["data"] else {}
        result.append(item)

    return result

@app.get("/listpublic", response_model=List[dict])
@limiter.limit("30/minute")
def list_public_entries(
    request: Request,
    db: sqlite3.Connection = Depends(get_db),
    type: Optional[str] = None,
    category: Optional[str] = None,
    keyword: Optional[str] = None,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    sql = "SELECT * FROM items WHERE status = 'published'"
    params = []

    if type:
        sql += " AND type = ?"
        params.append(type)

    if category:
        sql += " AND category = ?"
        params.append(category)

    if keyword:
        sql += " AND (title LIKE ? OR slug LIKE ?)"
        params.extend([f"%{keyword}%", f"%{keyword}%"])

    sql += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
    params.extend([limit, offset])

    rows = db.execute(sql, params).fetchall()
    result = []
    for row in rows:
        row = dict(row)
        result.append({
            "slug": row["slug"],
            "title": row["title"],
            "type": row["type"],
            "category": row["category"],
            "status": row["status"],
            "tags": json.loads(row["tags"]) if row["tags"] else [],
            "data": json.loads(row["data"]) if row["data"] else {},
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        })
    return result


@app.get("/retrieve/{slug}", response_model=dict)
@limiter.limit("30/minute")
def retrieve_entry(request: Request, slug: str, db: sqlite3.Connection = Depends(get_db)):
    row = db.execute(
        "SELECT * FROM items WHERE slug = ? AND status = 'published'", (slug,)
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Item not found")

    row = dict(row)
    return {
        "slug": row["slug"],
        "title": row["title"],
        "type": row["type"],
        "category": row["category"],
        "tags": json.loads(row["tags"]) if row["tags"] else [],
        "data": json.loads(row["data"]) if row["data"] else {},
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


@app.post("/create", response_model=Item, status_code=201)
@limiter.limit("15/minute")
def create_entry(
    request: Request,
    item: ItemCreate,
    current_user: AuthInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    logger.info(f"User '{current_user.user_id}' creating entry '{item.slug}'")
    try:
        cursor = safe_write(db, """
            INSERT INTO items (owner_id, slug, title, type, category, tags, status, data)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            current_user.user_id,
            item.slug,
            item.title,
            item.type,
            item.category,
            json.dumps(item.tags),
            item.status,
            json.dumps(item.data),
        ))
        db.commit()
    except sqlite3.IntegrityError:
         raise HTTPException(status_code=409, detail=f"Item with slug '{item.slug}' already exists.")

    new_item = db.execute("SELECT * FROM items WHERE id = ?", (cursor.lastrowid,)).fetchone()
    item_dict = dict(new_item)
    item_dict["tags"] = json.loads(item_dict["tags"]) if item_dict["tags"] else []
    item_dict["data"] = json.loads(item_dict["data"]) if item_dict["data"] else {}
    return item_dict

@app.put("/update/{slug}", response_model=Item)
@limiter.limit("15/minute")
def update_entry(
    request: Request,
    slug: str,
    item_update: ItemUpdate,
    current_user: AuthInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    existing_item = db.execute("SELECT owner_id FROM items WHERE slug = ?", (slug,)).fetchone()
    if not existing_item:
        raise HTTPException(status_code=404, detail="Item not found")
    if existing_item["owner_id"] != current_user.user_id:
        raise HTTPException(status_code=403, detail="Not authorized to update this item")

    safe_write(db, """
        UPDATE items
        SET title = ?, type = ?, category = ?, tags = ?, status = ?, data = ?, updated_at = CURRENT_TIMESTAMP
        WHERE slug = ?
    """, (
        item_update.title,
        item_update.type,
        item_update.category,
        json.dumps(item_update.tags),
        item_update.status,
        json.dumps(item_update.data),
        slug
    ))
    db.commit()
    updated_item = db.execute("SELECT * FROM items WHERE slug = ?", (slug,)).fetchone()
    item_dict = dict(updated_item)
    item_dict["tags"] = json.loads(item_dict["tags"]) if item_dict["tags"] else []
    item_dict["data"] = json.loads(item_dict["data"]) if item_dict["data"] else {}
    return item_dict

@app.delete("/delete/{slug}", status_code=200)
@limiter.limit("15/minute")
def delete_entry(
    request: Request,
    slug: str,
    current_user: AuthInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    existing_item = db.execute("SELECT owner_id FROM items WHERE slug = ?", (slug,)).fetchone()
    if not existing_item:
        raise HTTPException(status_code=404, detail="Item not found")
    if existing_item["owner_id"] != current_user.user_id:
        raise HTTPException(status_code=403, detail="Not authorized to delete this item")

    safe_write(db, "DELETE FROM items WHERE slug = ?", (slug,))
    db.commit()
    logger.info(f"User '{current_user.user_id}' deleted item with slug '{slug}'")
    return {"message": f"Item '{slug}' deleted successfully"}

@app.get("/search", response_model=List[dict])
@limiter.limit("30/minute")
def search_entries(
    request: Request,
    db: sqlite3.Connection = Depends(get_db),
    keyword: str = Query(..., description="Search keyword"),
):
    sql = "SELECT * FROM items WHERE status = 'published' AND (title LIKE ? OR slug LIKE ?) ORDER BY created_at DESC"
    param = f"%{keyword}%"
    rows = db.execute(sql, (param, param)).fetchall()

    result = []
    for row in rows:
        row = dict(row)
        result.append({
            "slug": row["slug"],
            "title": row["title"],
            "type": row["type"],
            "category": row["category"],
            "tags": json.loads(row["tags"]) if row["tags"] else [],
            "data": json.loads(row["data"]) if row["data"] else {},
            "created_at": row["created_at"],
            "updated_at": row["updated_at"],
        })
    return result

PYTHON
}

generate_storage_py() {
    local path=$1
    sudo tee "$path/main.py" >/dev/null << 'PYTHON'
import os
import aiofiles
import secrets
import sqlite3
from pathlib import Path
from dotenv import load_dotenv

from fastapi import FastAPI, Depends, HTTPException, UploadFile, File, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel
from typing import List

from helpers import get_current_user, setup_logger, limiter, AuthInfo, get_admin_access, get_db, safe_write

load_dotenv()
app = FastAPI(root_path="/v1/storage")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.state.limiter = limiter
logger = setup_logger("storage", f"../logs/storage/output.log")
UPLOAD_DIR = Path("files")
UPLOAD_DIR.mkdir(exist_ok=True)
DB_PATH = Path("storage.db")

def init_db():
    with sqlite3.connect(DB_PATH) as db:
        db.execute("PRAGMA journal_mode=WAL;")
        db.execute("""
        CREATE TABLE IF NOT EXISTS files (
            id TEXT PRIMARY KEY,
            owner_id TEXT NOT NULL,
            original_name TEXT NOT NULL,
            disk_path TEXT NOT NULL UNIQUE,
            content_type TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """)
        db.execute("CREATE INDEX IF NOT EXISTS idx_files_owner_id ON files(owner_id);")
        logger.info("Storage database initialized.")
init_db()

def sanitize_filename(filename: str) -> str:
    return "".join(c if c.isalnum() or c in "._-" else "_" for c in filename)

class FileMetadata(BaseModel):
    id: str
    owner_id: str
    original_name: str
    content_type: str

@app.get("/health")
def health():
    return {"status": "storage is healthy"}

@app.post("/upload", response_model=FileMetadata)
@limiter.limit("10/minute")
async def upload_file(
    request: Request,
    file: UploadFile = File(...),
    current_user: AuthInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    user_upload_dir = UPLOAD_DIR / current_user.user_id
    user_upload_dir.mkdir(exist_ok=True)
    
    secure_disk_name = f"{secrets.token_hex(8)}_{sanitize_filename(file.filename)}"
    file_path_on_disk = user_upload_dir / secure_disk_name
    
    try:
        async with aiofiles.open(file_path_on_disk, "wb") as f:
            while content := await file.read(1024 * 1024):
                await f.write(content)
    except Exception as e:
        logger.error(f"Upload failed: {e}")
        raise HTTPException(status_code=500, detail="Could not save file.")

    file_id = secrets.token_urlsafe(16)
    safe_write(db,
        "INSERT INTO files (id, owner_id, original_name, disk_path, content_type) VALUES (?, ?, ?, ?, ?)",
        (
            file_id,
            current_user.user_id,
            file.filename,
            str(file_path_on_disk),
            file.content_type,
        )
    )
    db.commit()
    
    logger.info(f"User '{current_user.user_id}' uploaded '{file.filename}' as file ID {file_id}")
    return {
        "id": file_id,
        "owner_id": current_user.user_id,
        "original_name": file.filename,
        "content_type": file.content_type,
    }

@app.get("/download/{file_id}")
@limiter.limit("60/minute")
async def download_file(request: Request, file_id: str, db: sqlite3.Connection = Depends(get_db)):
    result = db.execute(
        "SELECT disk_path FROM files WHERE id = ?", (file_id,)
    ).fetchone()
    
    if not result:
        raise HTTPException(status_code=404, detail="File not found in DB")
    
    file_path = Path(result[0])
    if not file_path.is_file():
        logger.error(f"File ID {file_id} found in DB but missing on disk at {file_path}")
        raise HTTPException(status_code=404, detail="File not found on disk")
        
    return FileResponse(file_path)

@app.get("/list", response_model=List[FileMetadata])
@limiter.limit("30/minute")
async def list_user_files(request: Request, current_user: AuthInfo = Depends(get_current_user), db: sqlite3.Connection = Depends(get_db)):
    db.row_factory = sqlite3.Row
    rows = db.execute(
        """
        SELECT id, owner_id, original_name, content_type
        FROM files
        WHERE owner_id = ?
        ORDER BY created_at DESC
        """,
        (current_user.user_id,)
    ).fetchall()
    return [dict(row) for row in rows]

@app.delete("/delete/{file_id}", status_code=200)
@limiter.limit("10/minute")
async def delete_file(
    request: Request,
    file_id: str,
    current_user: AuthInfo = Depends(get_current_user),
    db: sqlite3.Connection = Depends(get_db)
):
    
    db.row_factory = sqlite3.Row
    file_record = db.execute(
        "SELECT * FROM files WHERE id = ?", (file_id,)
    ).fetchone()

    if not file_record:
        raise HTTPException(status_code=404, detail="File not found")

    if file_record["owner_id"] != current_user.user_id:
        raise HTTPException(status_code=403, detail="Not authorized to delete this file")

    # remove from disk
    file_path = Path(file_record["disk_path"])
    if file_path.exists():
        file_path.unlink()
        logger.info(f"File physically removed: {file_path}")
    else:
        logger.warning(f"File metadata found but missing on disk: {file_path}")

    # remove from DB
    safe_write(db, "DELETE FROM files WHERE id = ?", (file_id,))
    db.commit()
    logger.info(f"User '{current_user.user_id}' deleted file ID {file_id}")

    return {
        "message": f"{file_record['original_name']} deleted successfully"
    }

@app.get("/listall", response_model=List[FileMetadata])
@limiter.limit("10/minute")
async def list_all_files(request: Request, _=Depends(get_admin_access), db: sqlite3.Connection = Depends(get_db)):
    db.row_factory = sqlite3.Row
    rows = db.execute("""
        SELECT id, owner_id, original_name, content_type
        FROM files
        ORDER BY created_at DESC
    """).fetchall()
    return [dict(row) for row in rows]

PYTHON
}

# --- NGINX & Manifest Functions ---
configure_nginx_and_certbot() {
    local has_website=$1 has_backend=$2
    local project=$3 api_domain=$4 frontend_domain=$5
    local selected_components=("${@:6}")
    local cert_domains=()

    log "Configuring NGINX reverse proxy..."
    
    if $has_backend; then
        local nginx_api_conf="/etc/nginx/sites-available/${project}-api.conf"
        sudo tee "$nginx_api_conf" > /dev/null <<EOF
server {
    listen 80;
    server_name $api_domain;

EOF
        for comp in "${selected_components[@]}"; do
            local port_val=""
            case $comp in
              auth) port_val=$PORT_AUTH ;;
              app) port_val=$PORT_APP ;;
              database) port_val=$PORT_DATABASE ;;
              storage) port_val=$PORT_STORAGE ;;
              *) continue ;;
            esac
            sudo tee -a "$nginx_api_conf" > /dev/null <<EOF
    location /v1/$comp/ {
        proxy_pass http://127.0.0.1:$port_val/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
EOF
        done

    sudo tee -a "$nginx_api_conf" > /dev/null <<EOF
    location / {
        return 404 '{"error": "Unknown API endpoint"}';
        add_header Content-Type application/json;
    }
EOF
        echo "}" | sudo tee -a "$nginx_api_conf" > /dev/null
        
        CREATED_NGINX_CONFS+=("$nginx_api_conf")
        sudo ln -sf "$nginx_api_conf" "/etc/nginx/sites-enabled/"
        CREATED_NGINX_LINKS+=("/etc/nginx/sites-enabled/$(basename "$nginx_api_conf")")
        cert_domains+=( -d "$api_domain" )
        log_ok "Created NGINX config for API services."
    fi

    if $has_website; then
        local nginx_web_conf="/etc/nginx/sites-available/${project}-web.conf"
        sudo tee "$nginx_web_conf" > /dev/null <<EOF
server {
  listen 80;
  server_name $frontend_domain;

  root $PROJECT_ROOT/$project/website;
  index index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }
  
  # Security Headers
  add_header X-Frame-Options "SAMEORIGIN";
  add_header X-Content-Type-Options "nosniff";
  add_header Referrer-Policy "strict-origin-when-cross-origin";
}
EOF
        CREATED_NGINX_CONFS+=("$nginx_web_conf")
        sudo ln -sf "$nginx_web_conf" "/etc/nginx/sites-enabled/"
        CREATED_NGINX_LINKS+=("/etc/nginx/sites-enabled/$(basename "$nginx_web_conf")")
        cert_domains+=( -d "$frontend_domain" )
        log_ok "Created NGINX config for website."
    fi

    log "Validating and reloading NGINX..."
    if ! sudo nginx -t; then
        err "NGINX configuration test failed. Please review the error message above. Rolling back."
    fi
    sudo systemctl reload nginx
    log_ok "NGINX reloaded successfully."

    if [ ${#cert_domains[@]} -gt 0 ]; then
        log "Requesting SSL certificates via Certbot..."
        local max_retries=3
        local attempt=1
        while [ $attempt -le $max_retries ]; do
            if sudo certbot --nginx --redirect --agree-tos --no-eff-email --non-interactive --expand "${cert_domains[@]}"; then
                log_ok "Certbot finished successfully on attempt $attempt."
                return 0
            else
                log_warn "Certbot failed on attempt $attempt of $max_retries. Retrying in 15 seconds..."
                sleep 15
                ((attempt++))
            fi
        done
        err "Certbot failed after $max_retries attempts. Please check logs and run manually. Rolling back."
    fi
}

create_project_manifest() {
    log "Creating project manifest file..."
    PROJECT_CONF_FILE="$APP_PATH/project.conf"
    {
      echo "# Project Configuration - v7.0.3"
      echo "PROJECT=\"$PROJECT\""
      echo "APP_PATH=\"$APP_PATH\""
      echo "HAS_WEBSITE=$HAS_WEBSITE"
      echo "HAS_BACKEND=$HAS_BACKEND"
      echo "FRONTEND_DOMAIN=\"$FRONTEND_DOMAIN\""
      echo "API_DOMAIN=\"$API_DOMAIN\""
      echo "SELECTED_COMPONENTS=(${SELECTED_COMPONENTS[*]})"
      echo "PORT_AUTH=$PORT_AUTH"
      echo "PORT_APP=$PORT_APP"
      echo "PORT_DATABASE=$PORT_DATABASE"
      echo "PORT_STORAGE=$PORT_STORAGE"
    } | sudo tee "$PROJECT_CONF_FILE" > /dev/null
    sudo chown "$APP_USER:$APP_USER" "$PROJECT_CONF_FILE"
    sudo chmod 640 "$PROJECT_CONF_FILE"
    log_ok "Created project manifest at '$PROJECT_CONF_FILE'."
}

create_logrotate_config() {
    local project=$1
    log "Creating logrotate configuration..."
    CREATED_LOGROTATE_CONF="/etc/logrotate.d/$project"
    sudo tee "$CREATED_LOGROTATE_CONF" > /dev/null <<EOF
/var/www/$project/logs/*/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF
    log_ok "Logrotate config created at $CREATED_LOGROTATE_CONF"
}

# --- Main Script Body ---
run_create_mode() {
    log "Starting project creation..."
    while true; do
      read -rp "Enter project name (lowercase, no spaces, e.g. my-portfolio): " PROJECT
      if [[ "$PROJECT" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
        [ -d "$PROJECT_ROOT/$PROJECT" ] && err "Project '$PROJECT' already exists." || break
      else
        echo "Invalid project name. Please use lowercase letters, numbers, and single hyphens."
      fi
    done
    
    APP_PATH="$PROJECT_ROOT/$PROJECT"
    APP_USER="app_$PROJECT"
    WEB_USER="web_$PROJECT"

    echo ""
    echo "Select components to create (space-separated numbers, e.g., '1 2 4'):"
    echo "  1) website   (Static frontend hosting with NGINX)"
    echo "  2) auth      (User login via 'magic link' email)"
    echo "  3) app       (Core business logic backend)"
    echo "  4) database  (Simple SQLite data API)"
    echo "  5) storage   (Secure file upload/download API)"
    read -rp "Your choice: " CHOICE
    
    SELECTED_COMPONENTS=()
    [[ "$CHOICE" =~ "1" ]] && SELECTED_COMPONENTS+=("website")
    [[ "$CHOICE" =~ "2" ]] && SELECTED_COMPONENTS+=("auth")
    [[ "$CHOICE" =~ "3" ]] && SELECTED_COMPONENTS+=("app")
    [[ "$CHOICE" =~ "4" ]] && SELECTED_COMPONENTS+=("database")
    [[ "$CHOICE" =~ "5" ]] && SELECTED_COMPONENTS+=("storage")

    if [ ${#SELECTED_COMPONENTS[@]} -eq 0 ]; then
      err "No components selected. Aborting."
    fi

    # CRITICAL FIX: These are now global to be accessible by the final summary message in main()
    HAS_WEBSITE=false
    HAS_BACKEND=false
    for comp in "${SELECTED_COMPONENTS[@]}"; do
      if [[ "$comp" == "website" ]]; then HAS_WEBSITE=true;
      else HAS_BACKEND=true; fi
    done

    FRONTEND_DOMAIN=""
    API_DOMAIN=""
    local RESEND_API_KEY=""

    if $HAS_WEBSITE; then
      read -rp "Enter frontend domain (e.g. my-portfolio.com): " FRONTEND_DOMAIN
    fi
    if $HAS_BACKEND; then
      read -rp "Enter API domain (e.g. api.my-portfolio.com): " API_DOMAIN
    fi
    if printf '%s\n' "${SELECTED_COMPONENTS[@]}" | grep -q '^auth$'; then
      read -rsp "Enter your Resend API Key (will not be shown, edit later in .env): " RESEND_API_KEY
      echo ""
      if [ -z "$RESEND_API_KEY" ]; then
        log_warn "No Resend API Key provided. The 'auth' service will be created, but it will NOT be able to send login emails."
      fi
      read -rp "Enter the FROM email address for Resend (e.g. login@mydomain.com, edit later in .env, leave empty for default): " RESEND_FROM_EMAIL
      if [ -z "$RESEND_FROM_EMAIL" ]; then
        RESEND_FROM_EMAIL="onboarding@resend.dev"
        log_warn "No from-address provided, defaulting to $RESEND_FROM_EMAIL"
      fi
    fi

    log "Provisioning system users and directory structure..."
    sudo adduser --system --group --no-create-home "$APP_USER" && CREATED_USERS+=("$APP_USER")
    log_ok "Created system user '$APP_USER' for backend services."
    if $HAS_WEBSITE; then
      sudo adduser --system --group --no-create-home "$WEB_USER" && CREATED_USERS+=("$WEB_USER")
      log_ok "Created system user '$WEB_USER' for website files."
    fi
    
    sudo mkdir -p "$APP_PATH" && CREATED_DIRS+=("$APP_PATH")
    sudo chown "$APP_USER:$APP_USER" "$APP_PATH"
    sudo chmod 751 "$APP_PATH"
    log_ok "Created project root at '$APP_PATH'."

    log "Generating secrets and assigning network ports..."
    local JWT_SECRET=$(openssl rand -hex 32)
    log_ok "Generated secure JWT Secret."

    local BASE_ID=$(echo "$PROJECT" | cksum | cut -d' ' -f1)
    local OFFSET=$((BASE_ID % 1000))
    PORT_AUTH=$((API_PORT_START + OFFSET))
    PORT_APP=$((PORT_AUTH + 1))
    PORT_DATABASE=$((PORT_AUTH + 2))
    PORT_STORAGE=$((PORT_AUTH + 3))
    log_ok "Assigned stable ports for services."

    for component in "${SELECTED_COMPONENTS[@]}"; do
      log "Configuring '$component' component..."
      sudo mkdir -p "$APP_PATH/$component"
      
      if [[ "$component" == "website" ]]; then
        sudo chown -R "$WEB_USER:$WEB_USER" "$APP_PATH/$component"
        sudo chmod -R 755 "$APP_PATH/$component"
        sudo tee "$APP_PATH/$component/index.html" >/dev/null << EOF
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
    <link rel="icon" type="image/svg+xml" href='data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="50" cy="50" r="50" fill="%23ffae09"/></svg>'>
    <title>Welcome to KCstudio Launchpad Toolkit</title>
    <style>
      body {
        margin: 0;
        background: #ffffff;
        color: #000000;
        font-family: Verdana;
        display: flex;
        align-items: center;
        justify-content: center;
        height: 100vh;
        text-align: center;
        flex-direction: column;
      }
      h1 {
        font-size: 40px;
        margin-bottom: 10px;
      }
      p {
        font-size: 18px;
        color: #555;
      }
      .footer {
        padding-top:30px;
        padding-bottom:40px;
        bottom: 20px;
        font-size: 12px;
        color: #999;
      }
      .badge {
        background-color: #000;
        color: #fff;
        padding: 8px 16px;
        border-radius: 5px;
        margin-top: 20px;
        text-decoration: none;
        display: inline-block;
      }
      .social {
        margin-top: 20px;
      }
      .social a {
        margin: 0 10px;
        color: #999;
        text-decoration: none;
        font-size: 14px;
      }
      .social svg {
        vertical-align: middle;
        margin-right: 5px;
      }
    </style>
  </head>
  <body>
  <img src="https://launchpad.kcstudio.nl/img/KCstudio_Launchpad_Logo.png" alt="KCstudio Logo" style="max-width:125px; height:auto; margin-bottom:1vw; padding-top:2vw;" />
    <h1>KCstudio Launchpad</h1>
    <p>Fullstack Toolkit Creator and Manager</p>
    <p>Welcome to your project: <strong>$PROJECT</strong></p>
    <a class="badge" href="https://launchpad.kcstudio.nl">Test your backend here!</a>
    <div class="social">
      <br>
      <a href="https://github.com/kelvincdeen/kcstudio-launchpad-toolkit" target="_blank">
        <svg fill="#999999" height="24" viewBox="0 0 24 24">
          <path d="M12 .5C5.6.5.5 5.6.5 12c0 5.1 3.3 9.4 7.9 10.9.6.1.8-.3.8-.6v-2c-3.2.7-3.9-1.5-3.9-1.5-.5-1.3-1.1-1.7-1.1-1.7-.9-.6.1-.6.1-.6 1 .1 1.5 1 1.5 1 .9 1.5 2.3 1 2.9.8.1-.7.4-1 .7-1.2-2.5-.3-5.1-1.2-5.1-5.4 0-1.2.4-2.1 1-2.8-.1-.3-.4-1.4.1-2.9 0 0 .8-.3 2.8 1a9.7 9.7 0 012.5-.3c.8 0 1.6.1 2.5.3 2-.1 2.8-1 2.8-1 .5 1.5.2 2.6.1 2.9.6.7 1 1.6 1 2.8 0 4.2-2.6 5.1-5.1 5.4.4.3.7.9.7 1.8v2.7c0 .3.2.7.8.6A10.5 10.5 0 0023.5 12C23.5 5.6 18.4.5 12 .5z"/>
        </svg>GitHub
      </a>
      <a href="https://kcstudio.nl" target="_blank">
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-folder-code-icon lucide-folder-code"><path d="M10 10.5 8 13l2 2.5"/><path d="m14 10.5 2 2.5-2 2.5"/><path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2z"/></svg>KCstudio
      </a>
    </div>
    <div class="footer">
  <!-- 
    Hey there! This site was built with KCstudio Launchpad Toolkit. 
    If you found this tool useful, I'd be grateful if you kept this link. Or star me on GitHub. Or buy me a coffee.
    It's not required, but it helps a lot! Thanks :)
  -->
      Generated by KCstudio Launchpad
    </div>
  </body>
</html>
EOF

        log_ok "Created 'website' directory and set permissions."
      else
        sudo mkdir -p "$APP_PATH/logs/$component"
        sudo touch "$APP_PATH/logs/$component/output.log"
        sudo chown -R "$APP_USER:$APP_USER" "$APP_PATH/$component" "$APP_PATH/logs"
        sudo chmod -R 770 "$APP_PATH/$component" "$APP_PATH/logs"
        log_ok "Created '$component' directory with logging and permissions."

        generate_python_helpers "$APP_PATH/$component"
        case "$component" in
          auth)     generate_auth_py "$APP_PATH/$component" ;;
          app)      generate_app_py "$APP_PATH/$component" ;;
          database) generate_database_py "$APP_PATH/$component" ;;
          storage)  generate_storage_py "$APP_PATH/$component" ;;
        esac
        log_ok "Generated main.py logic for '$component'."

        local deps="fastapi uvicorn python-dotenv slowapi requests PyJWT"
        if [[ "$component" == "auth" ]]; then deps+=" resend pydantic[email]"; fi
        if [[ "$component" == "storage" ]]; then deps+=" aiofiles python-multipart"; fi

        log_ok "Installing Python dependencies for '$component'..."
        sudo -u "$APP_USER" bash -c "cd '$APP_PATH/$component' && python3 -m venv venv && source venv/bin/activate && pip --no-cache-dir install --upgrade pip > /dev/null && pip --no-cache-dir install $deps > /dev/null"
        log_ok "Installed Python dependencies for '$component'."

        local port_val=""
        case "$component" in
            auth) port_val=$PORT_AUTH ;;
            app) port_val=$PORT_APP ;;
            database) port_val=$PORT_DATABASE ;;
            storage) port_val=$PORT_STORAGE ;;
        esac

        {
          echo "APP_PORT=$port_val"
          echo "API_DOMAIN=$API_DOMAIN"
          echo "FRONTEND_DOMAIN=$FRONTEND_DOMAIN"
          echo "JWT_SECRET=$JWT_SECRET"
          echo "ADMIN_API_KEY=$(openssl rand -hex 32)"
          if [[ "$component" == "auth" ]]; then
            echo "RESEND_API_KEY=$RESEND_API_KEY"
            echo "RESEND_FROM_EMAIL=$RESEND_FROM_EMAIL"
          fi
          if [[ "$component" == "auth" ]]; then
            echo "DB_PATH=users.db"
          elif [[ "$component" == "database" ]]; then
            echo "DB_PATH=data.db"
          elif [[ "$component" == "storage" ]]; then
            echo "DB_PATH=storage.db"
          fi
        } | sudo tee "$APP_PATH/$component/.env" > /dev/null
        sudo chown "$APP_USER:$APP_USER" "$APP_PATH/$component/.env"
        sudo chmod 660 "$APP_PATH/$component/.env"
        log_ok "Created secure .env file for '$component'."

        local service_name="${PROJECT}-${component}"
        sudo tee "/etc/systemd/system/$service_name.service" > /dev/null <<SVC
[Unit]
Description=$PROJECT $component service
After=network.target
[Service]
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_PATH/$component
EnvironmentFile=$APP_PATH/$component/.env
ExecStart=$APP_PATH/$component/venv/bin/uvicorn main:app --host 127.0.0.1 --port \$APP_PORT
Restart=always
RestartSec=3
StandardOutput=append:$APP_PATH/logs/$component/output.log
StandardError=append:$APP_PATH/logs/$component/output.log
[Install]
WantedBy=multi-user.target
SVC
        CREATED_SERVICES+=("$service_name.service")
        log_ok "Created systemd service file for '$component'."
      fi
    done

    if $HAS_BACKEND; then
      create_logrotate_config "$PROJECT"
      log "Starting and enabling all backend services..."
      sudo systemctl daemon-reload
      for service in "${CREATED_SERVICES[@]}"; do
          sudo systemctl enable --now "$service"
          log_ok "Started and enabled $service."
      done
    fi

    if $HAS_WEBSITE || $HAS_BACKEND; then
      configure_nginx_and_certbot "$HAS_WEBSITE" "$HAS_BACKEND" "$PROJECT" "$API_DOMAIN" "$FRONTEND_DOMAIN" "${SELECTED_COMPONENTS[@]}"
    fi

    create_project_manifest
}

run_restore_mode() {
    log "Starting project restoration..."
    read -rp "Enter the full path to the backup file (.tar.gz): " backup_path
    
    if [[ ! -f "$backup_path" ]]; then
        err "Backup file not found at '$backup_path'."
    fi

    log "Analyzing backup file..."
    local temp_restore_dir
    temp_restore_dir=$(mktemp -d)
    
    trap 'sudo rm -rf "$temp_restore_dir"' EXIT
    
    tar -xzf "$backup_path" -C "$temp_restore_dir"
    
    local backup_project_dir
    backup_project_dir=$(find "$temp_restore_dir" -mindepth 1 -maxdepth 1 -type d)
    
    if [[ ! -f "$backup_project_dir/project.conf" ]]; then
        err "Backup is invalid or corrupted (missing project.conf)."
    fi

    # shellcheck source=/dev/null
    source "$backup_project_dir/project.conf"
    log_ok "Backup manifest loaded for project '$PROJECT'."

    APP_PATH="$PROJECT_ROOT/$PROJECT"
    APP_USER="app_$PROJECT"
    WEB_USER="web_$PROJECT"

    if [ -d "$APP_PATH" ]; then
        err "A project named '$PROJECT' already exists. Please remove it before restoring."
    fi
    
    # CRITICAL FIX: The port variables are sourced but need to be accessible globally for this function
    PORT_AUTH=${PORT_AUTH:-}
    PORT_APP=${PORT_APP:-}
    PORT_DATABASE=${PORT_DATABASE:-}
    PORT_STORAGE=${PORT_STORAGE:-}

    log "Provisioning system users and directory structure for restoration..."
    sudo adduser --system --group --no-create-home "$APP_USER" && CREATED_USERS+=("$APP_USER")
    log_ok "Created system user '$APP_USER'."
    if [[ "$HAS_WEBSITE" == "true" ]]; then
      sudo adduser --system --group --no-create-home "$WEB_USER" && CREATED_USERS+=("$WEB_USER")
      log_ok "Created system user '$WEB_USER'."
    fi

    log "Restoring project files from backup..."
    sudo mv "$backup_project_dir" "$APP_PATH"
    CREATED_DIRS+=("$APP_PATH")
    
    sudo chown -R "$APP_USER:$APP_USER" "$APP_PATH"
    sudo chmod 751 "$APP_PATH"
    if [[ "$HAS_WEBSITE" == "true" ]]; then
      sudo chown -R "$WEB_USER:$WEB_USER" "$APP_PATH/website"
    fi
    log_ok "Project files restored and permissions set."
    
    log "Re-installing Python dependencies..."
    for component in "${SELECTED_COMPONENTS[@]}"; do
      if [[ "$component" != "website" ]]; then
        if [ -d "$APP_PATH/$component/venv" ]; then
            log_warn "Existing venv found in backup for '$component'. Re-running pip install to ensure compatibility."
        fi
        local deps="fastapi uvicorn python-dotenv slowapi requests PyJWT"
        if [[ "$component" == "auth" ]]; then deps+=" resend pydantic[email]"; fi
        if [[ "$component" == "storage" ]]; then deps+=" aiofiles python-multipart"; fi
        
        sudo -u "$APP_USER" bash -c "cd '$APP_PATH/$component' && python3 -m venv venv && source venv/bin/activate && pip --no-cache-dir install --upgrade pip > /dev/null && pip --no-cache-dir install $deps > /dev/null"
        log_ok "Dependencies ensured for '$component'."

        local port_val_var="PORT_${component^^}"
        local port_val="${!port_val_var}"

        local service_name="${PROJECT}-${component}"
        sudo tee "/etc/systemd/system/$service_name.service" > /dev/null <<SVC
[Unit]
Description=$PROJECT $component service (Restored)
After=network.target
[Service]
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_PATH/$component
EnvironmentFile=$APP_PATH/$component/.env
ExecStart=$APP_PATH/$component/venv/bin/uvicorn main:app --host 127.0.0.1 --port $port_val
Restart=always
RestartSec=3
StandardOutput=append:$APP_PATH/logs/$component/output.log
StandardError=append:$APP_PATH/logs/$component/output.log
[Install]
WantedBy=multi-user.target
SVC
        CREATED_SERVICES+=("$service_name.service")
        log_ok "Created systemd service file for '$component'."
      fi
    done
    
    if [[ "$HAS_BACKEND" == "true" ]]; then
      create_logrotate_config "$PROJECT"
      log "Starting and enabling all restored backend services..."
      sudo systemctl daemon-reload
      for service in "${CREATED_SERVICES[@]}"; do
          sudo systemctl enable --now "$service"
          log_ok "Started and enabled $service."
      done
    fi

    if [[ "$HAS_WEBSITE" == "true" || "$HAS_BACKEND" == "true" ]]; then
      configure_nginx_and_certbot "$HAS_WEBSITE" "$HAS_BACKEND" "$PROJECT" "$API_DOMAIN" "$FRONTEND_DOMAIN" "${SELECTED_COMPONENTS[@]}"
    fi
}


main() {
    trap cleanup ERR EXIT
    clear
    echo -e "‘\033[1;37m" # Set color to white
    cat << 'EOF'
██╗  ██╗ ██████╗███████╗████████╗██╗   ██╗██████╗ ██╗ ██████╗    ███╗   ██╗██╗     
██║ ██╔╝██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗██║██╔═══██╗   ████╗  ██║██║     
█████╔╝ ██║     ███████╗   ██║   ██║   ██║██║  ██║██║██║   ██║   ██╔██╗ ██║██║     
██╔═██╗ ██║     ╚════██║   ██║   ██║   ██║██║  ██║██║██║   ██║   ██║╚██╗██║██║     
██║  ██╗╚██████╗███████║   ██║   ╚██████╔╝██████╔╝██║╚██████╔╝██╗██║ ╚████║███████╗
╚═╝  ╚═╝ ╚═════╝╚══════╝   ╚═╝    ╚═════╝ ╚═════╝ ╚═╝ ╚═════╝ ╚═╝╚═╝  ╚═══╝╚══════╝
EOF
    echo -e "\e[0m" # Reset color
    
    log "Advanced Project Architect v9.2"
    echo "This script can create a new project from scratch or restore one from a backup."
    
    # Declare variables used in the final summary so they have global scope
    PROJECT=""
    HAS_WEBSITE=false
    HAS_BACKEND=false
    FRONTEND_DOMAIN=""
    API_DOMAIN=""

    local choice
    read -rp "Choose an action: (C)reate new project, or (R)estore from backup: " choice
    
    case $choice in
        [Cc]*)
            run_create_mode
            ;;
        [Rr]*)
            run_restore_mode
            ;;
        *)
            err "Invalid choice. Please enter 'C' or 'R'."
            ;;
    esac

    log "✅ Operation completed successfully for project '$PROJECT'!"
    echo "-----------------------------------------------------"
    if [[ "$HAS_WEBSITE" == "true" ]]; then echo "Frontend URL: https://$FRONTEND_DOMAIN"; fi
    if [[ "$HAS_BACKEND" == "true" ]]; then echo "API Base URL: https://$API_DOMAIN/v1/"; fi
    echo ""
    echo "You can now manage this project with:"
    echo "  ./manageApp.sh $PROJECT"
    echo "-----------------------------------------------------"

    trap - ERR EXIT
}

# --- Execute Main ---
main