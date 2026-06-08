"""
CloudMart User Service
Manages user registration, authentication (JWT), and profile management.

Data Store:
  - Default: In-memory dictionary (for local dev / Docker Compose)
  - Cloud:   Set DB_BACKEND=postgres via env var to use managed PostgreSQL
             (RDS / Cloud SQL / Azure Database for PostgreSQL)
"""

import json
import os
import uuid
import logging
from datetime import datetime, timedelta
from functools import wraps

from flask import Flask, jsonify, request, abort
import bcrypt
import jwt as pyjwt
from flask_cors import CORS

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------
app = Flask(__name__)
CORS(app, origins=["http://localhost:3000"])
app.config["JSON_SORT_KEYS"] = False

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("user-service")

JWT_EXPIRY_HOURS = int(os.environ.get("JWT_EXPIRY_HOURS", "24"))

# ---------------------------------------------------------------------------
# In-memory data store
# ---------------------------------------------------------------------------

users_db = {}

# Seed data — password for all seed users is "password123"
_hashed_pw = bcrypt.hashpw(b"password123", bcrypt.gensalt()).decode("utf-8")

SEED_USERS = [
    {
        "id": "user-001",
        "email": "alice@cloudmart.example",
        "name": "Alice Fernando",
        "passwordHash": _hashed_pw,
        "role": "customer",
        "address": "42 Galle Road, Colombo 03, Sri Lanka",
        "createdAt": "2025-01-10T08:00:00Z",
    },
    {
        "id": "user-002",
        "email": "bob@cloudmart.example",
        "name": "Bob Perera",
        "passwordHash": _hashed_pw,
        "role": "customer",
        "address": "15 Kandy Road, Peradeniya, Sri Lanka",
        "createdAt": "2025-01-12T10:00:00Z",
    },
    {
        "id": "user-admin",
        "email": "admin@cloudmart.example",
        "name": "CloudMart Admin",
        "passwordHash": _hashed_pw,
        "role": "admin",
        "address": "",
        "createdAt": "2025-01-01T00:00:00Z",
    },
]

for u in SEED_USERS:
    users_db[u["id"]] = dict(u)


# ---------------------------------------------------------------------------
# AWS Secrets Manager (production — credentials via IRSA)
# ---------------------------------------------------------------------------


def _load_secret_json(secret_id):
    import boto3

    region = os.environ.get("AWS_REGION", "ap-south-1")
    client = boto3.client("secretsmanager", region_name=region)
    response = client.get_secret_value(SecretId=secret_id)
    return json.loads(response["SecretString"])


def load_aws_secrets():
    """Load DB and JWT credentials from Secrets Manager when configured."""
    db_secret = os.environ.get("DB_SECRET_NAME") or os.environ.get("DB_SECRET_ARN")
    jwt_secret = os.environ.get("JWT_SECRET_NAME") or os.environ.get("JWT_SECRET_ARN")

    if not db_secret and not jwt_secret:
        return

    try:
        if db_secret:
            data = _load_secret_json(db_secret)
            os.environ.setdefault("DB_HOST", str(data.get("DB_HOST", "")))
            os.environ.setdefault("DB_PORT", str(data.get("DB_PORT", "5432")))
            os.environ.setdefault("DB_NAME", str(data.get("DB_NAME", "")))
            os.environ.setdefault(
                "DB_USER",
                str(data.get("DB_USER") or data.get("DB_USERNAME", "")),
            )
            os.environ.setdefault("DB_PASSWORD", str(data.get("DB_PASSWORD", "")))
            logger.info("Loaded database credentials from Secrets Manager")

        if jwt_secret:
            data = _load_secret_json(jwt_secret)
            os.environ.setdefault("JWT_SECRET", str(data.get("JWT_SECRET", "")))
            logger.info("Loaded JWT secret from Secrets Manager")
    except Exception as exc:
        logger.error("Failed to load secrets from Secrets Manager: %s", exc)
        raise


load_aws_secrets()
JWT_SECRET = os.environ.get("JWT_SECRET", "cloudmart-dev-secret-change-in-production")

# ---------------------------------------------------------------------------
# Database abstraction
# ---------------------------------------------------------------------------


class InMemoryUserStore:
    """In-memory user store for local development."""

    def find_by_email(self, email):
        for user in users_db.values():
            if user["email"] == email:
                return user
        return None

    def find_by_id(self, user_id):
        return users_db.get(user_id)

    def create(self, user_data):
        users_db[user_data["id"]] = user_data
        return user_data

    def update(self, user_id, data):
        user = users_db.get(user_id)
        if not user:
            return None
        for key in ["name", "address", "email"]:
            if key in data:
                user[key] = data[key]
        user["updatedAt"] = datetime.utcnow().isoformat() + "Z"
        return user

    def list_all(self):
        return list(users_db.values())

    def is_ready(self):
        return True


class PostgresUserStore:
    """
    PostgreSQL adapter for managed RDS.

    Set DB_BACKEND=postgres and provide DB_HOST, DB_PORT, DB_NAME, DB_USER,
    DB_PASSWORD via environment variables or Secrets Manager (DB_SECRET_NAME).
    """

    def __init__(self):
        import psycopg2
        from psycopg2.extras import RealDictCursor

        self._psycopg2 = psycopg2
        self._RealDictCursor = RealDictCursor
        self._conn = None
        self._connect()
        self._init_schema()
        self._seed_users()

    def _db_config(self):
        if os.environ.get("DATABASE_URL"):
            return {"dsn": os.environ["DATABASE_URL"]}

        required = ["DB_HOST", "DB_NAME", "DB_USER", "DB_PASSWORD"]
        missing = [key for key in required if not os.environ.get(key)]
        if missing:
            raise ValueError(f"Missing required database environment variables: {', '.join(missing)}")

        return {
            "host": os.environ["DB_HOST"],
            "port": int(os.environ.get("DB_PORT", "5432")),
            "dbname": os.environ["DB_NAME"],
            "user": os.environ["DB_USER"],
            "password": os.environ["DB_PASSWORD"],
            "sslmode": os.environ.get("DB_SSLMODE", "require"),
            "connect_timeout": int(os.environ.get("DB_CONNECT_TIMEOUT", "10")),
        }

    def _connect(self):
        config = self._db_config()
        if "dsn" in config:
            self._conn = self._psycopg2.connect(config["dsn"])
        else:
            self._conn = self._psycopg2.connect(**config)
        self._conn.autocommit = True
        logger.info("Connected to PostgreSQL at %s", os.environ.get("DB_HOST", "DATABASE_URL"))

    def _cursor(self):
        if self._conn is None or self._conn.closed:
            self._connect()
        return self._conn.cursor(cursor_factory=self._RealDictCursor)

    def _init_schema(self):
        with self._cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS users (
                    id VARCHAR(64) PRIMARY KEY,
                    email VARCHAR(255) UNIQUE NOT NULL,
                    name VARCHAR(255) NOT NULL,
                    password_hash TEXT NOT NULL,
                    role VARCHAR(32) NOT NULL DEFAULT 'customer',
                    address TEXT DEFAULT '',
                    created_at TIMESTAMPTZ NOT NULL,
                    updated_at TIMESTAMPTZ
                )
                """
            )

    def _seed_users(self):
        with self._cursor() as cur:
            for user in SEED_USERS:
                cur.execute(
                    """
                    INSERT INTO users (id, email, name, password_hash, role, address, created_at)
                    VALUES (%(id)s, %(email)s, %(name)s, %(password_hash)s, %(role)s, %(address)s, %(created_at)s)
                    ON CONFLICT (id) DO NOTHING
                    """,
                    {
                        "id": user["id"],
                        "email": user["email"],
                        "name": user["name"],
                        "password_hash": user["passwordHash"],
                        "role": user["role"],
                        "address": user["address"],
                        "created_at": user["createdAt"],
                    },
                )

    @staticmethod
    def _row_to_user(row):
        if not row:
            return None
        user = {
            "id": row["id"],
            "email": row["email"],
            "name": row["name"],
            "passwordHash": row["password_hash"],
            "role": row["role"],
            "address": row["address"] or "",
            "createdAt": row["created_at"].isoformat().replace("+00:00", "Z"),
        }
        if row.get("updated_at"):
            user["updatedAt"] = row["updated_at"].isoformat().replace("+00:00", "Z")
        return user

    def find_by_email(self, email):
        with self._cursor() as cur:
            cur.execute("SELECT * FROM users WHERE email = %s", (email,))
            return self._row_to_user(cur.fetchone())

    def find_by_id(self, user_id):
        with self._cursor() as cur:
            cur.execute("SELECT * FROM users WHERE id = %s", (user_id,))
            return self._row_to_user(cur.fetchone())

    def create(self, user_data):
        with self._cursor() as cur:
            cur.execute(
                """
                INSERT INTO users (id, email, name, password_hash, role, address, created_at)
                VALUES (%(id)s, %(email)s, %(name)s, %(password_hash)s, %(role)s, %(address)s, %(created_at)s)
                RETURNING *
                """,
                {
                    "id": user_data["id"],
                    "email": user_data["email"],
                    "name": user_data["name"],
                    "password_hash": user_data["passwordHash"],
                    "role": user_data["role"],
                    "address": user_data.get("address", ""),
                    "created_at": user_data["createdAt"],
                },
            )
            return self._row_to_user(cur.fetchone())

    def update(self, user_id, data):
        fields = []
        values = []
        for key, column in [("name", "name"), ("address", "address"), ("email", "email")]:
            if key in data:
                fields.append(f"{column} = %s")
                values.append(data[key])

        if not fields:
            return self.find_by_id(user_id)

        values.append(user_id)
        query = f"UPDATE users SET {', '.join(fields)}, updated_at = NOW() WHERE id = %s RETURNING *"

        with self._cursor() as cur:
            cur.execute(query, values)
            return self._row_to_user(cur.fetchone())

    def list_all(self):
        with self._cursor() as cur:
            cur.execute("SELECT * FROM users ORDER BY created_at")
            return [self._row_to_user(row) for row in cur.fetchall()]

    def is_ready(self):
        try:
            with self._cursor() as cur:
                cur.execute("SELECT 1")
                cur.fetchone()
            return True
        except Exception as exc:
            logger.warning("PostgreSQL readiness check failed: %s", exc)
            return False


def create_user_store():
    backend = os.environ.get("DB_BACKEND", "memory").lower()
    if backend == "postgres":
        logger.info("Using PostgreSQL user store")
        return PostgresUserStore()
    logger.info("Using in-memory user store (set DB_BACKEND=postgres for cloud DB)")
    return InMemoryUserStore()


user_store = create_user_store()

# ---------------------------------------------------------------------------
# JWT helpers
# ---------------------------------------------------------------------------


def generate_token(user):
    """Generate a JWT token for an authenticated user."""
    payload = {
        "sub": user["id"],
        "email": user["email"],
        "name": user["name"],
        "role": user["role"],
        "iat": datetime.utcnow(),
        "exp": datetime.utcnow() + timedelta(hours=JWT_EXPIRY_HOURS),
    }
    return pyjwt.encode(payload, JWT_SECRET, algorithm="HS256")


def require_auth(f):
    """Decorator to require a valid JWT token."""

    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "Unauthorized", "message": "Missing or invalid Authorization header"}), 401
        token = auth_header.split(" ", 1)[1]
        try:
            payload = pyjwt.decode(token, JWT_SECRET, algorithms=["HS256"])
            request.user = payload
        except pyjwt.ExpiredSignatureError:
            return jsonify({"error": "Unauthorized", "message": "Token has expired"}), 401
        except pyjwt.InvalidTokenError:
            return jsonify({"error": "Unauthorized", "message": "Invalid token"}), 401
        return f(*args, **kwargs)

    return decorated


def safe_user(user):
    """Return user dict without password hash."""
    return {k: v for k, v in user.items() if k != "passwordHash"}


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.route("/health")
def health():
    return jsonify({"status": "healthy", "service": "user-service"})


@app.route("/ready")
def ready():
    if not user_store.is_ready():
        return jsonify({"status": "not ready", "service": "user-service"}), 503
    return jsonify({"status": "ready", "service": "user-service"})


@app.route("/auth/register", methods=["POST"])
def register():
    """Register a new user."""
    data = request.get_json()
    if not data:
        abort(400, description="Request body required")

    email = data.get("email", "").strip().lower()
    password = data.get("password", "")
    name = data.get("name", "")

    if not email or not password or not name:
        abort(400, description="Missing required fields: email, password, name")

    if len(password) < 8:
        abort(400, description="Password must be at least 8 characters")

    if user_store.find_by_email(email):
        abort(409, description=f"Email {email} is already registered")

    password_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

    user = {
        "id": f"user-{uuid.uuid4().hex[:8]}",
        "email": email,
        "name": name,
        "passwordHash": password_hash,
        "role": "customer",
        "address": data.get("address", ""),
        "createdAt": datetime.utcnow().isoformat() + "Z",
    }

    user_store.create(user)
    token = generate_token(user)
    logger.info("User registered: %s — %s", user["id"], email)

    return jsonify({"user": safe_user(user), "token": token}), 201


@app.route("/auth/login", methods=["POST"])
def login():
    """Authenticate a user and return a JWT token."""
    data = request.get_json()
    if not data:
        abort(400, description="Request body required")

    email = data.get("email", "").strip().lower()
    password = data.get("password", "")

    if not email or not password:
        abort(400, description="Missing required fields: email, password")

    user = user_store.find_by_email(email)
    if not user:
        return jsonify({"error": "Unauthorized", "message": "Invalid email or password"}), 401

    if not bcrypt.checkpw(password.encode("utf-8"), user["passwordHash"].encode("utf-8")):
        return jsonify({"error": "Unauthorized", "message": "Invalid email or password"}), 401

    token = generate_token(user)
    logger.info("User logged in: %s — %s", user["id"], email)

    return jsonify({"user": safe_user(user), "token": token})


@app.route("/auth/verify", methods=["GET"])
@require_auth
def verify_token():
    """Verify a JWT token and return the user info."""
    return jsonify({"valid": True, "user": request.user})


@app.route("/users/me", methods=["GET"])
@require_auth
def get_my_profile():
    """Get the current user's profile."""
    user = user_store.find_by_id(request.user["sub"])
    if not user:
        abort(404, description="User not found")
    return jsonify(safe_user(user))


@app.route("/users/me", methods=["PUT"])
@require_auth
def update_my_profile():
    """Update the current user's profile."""
    data = request.get_json()
    if not data:
        abort(400, description="Request body required")

    user = user_store.update(request.user["sub"], data)
    if not user:
        abort(404, description="User not found")

    logger.info("User updated profile: %s", user["id"])
    return jsonify(safe_user(user))


@app.route("/users/<user_id>", methods=["GET"])
def get_user(user_id):
    """Get a user by ID (public profile info only)."""
    user = user_store.find_by_id(user_id)
    if not user:
        abort(404, description=f"User {user_id} not found")
    return jsonify({"id": user["id"], "name": user["name"], "createdAt": user["createdAt"]})


# ---------------------------------------------------------------------------
# Error handlers
# ---------------------------------------------------------------------------


@app.errorhandler(400)
def bad_request(e):
    return jsonify({"error": "Bad Request", "message": str(e.description)}), 400


@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "Not Found", "message": str(e.description)}), 404


@app.errorhandler(409)
def conflict(e):
    return jsonify({"error": "Conflict", "message": str(e.description)}), 409


@app.errorhandler(500)
def internal_error(e):
    logger.error("Internal Server Error: %s", e)
    return jsonify({"error": "Internal Server Error"}), 500


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8003))
    debug = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
    logger.info("Starting user-service on port %s", port)
    app.run(host="0.0.0.0", port=port, debug=debug)
