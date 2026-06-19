"""
CloudMart Product Service
Manages product catalogue: CRUD operations, search, category filtering.

Data Store:
  - Default: In-memory dictionary (for local dev / Docker Compose)
  - Cloud:   Set STORE_BACKEND=dynamodb|firestore|cosmosdb via env var
             to use a managed NoSQL database (requires workload identity / credentials)
"""

import os
import uuid
import logging
from decimal import Decimal
from datetime import datetime
from flask import Flask, jsonify, request, abort
from flask_cors import CORS
import boto3
from botocore.exceptions import ClientError

# Seed data
SEED_PRODUCTS = [
    {
        "id": "prod-001",
        "name": "Wireless Bluetooth Headphones",
        "description": "Premium noise-cancelling over-ear headphones with 30-hour battery life",
        "price": 79.99,
        "category": "electronics",
        "stock": 150,
        "imageUrl": "/images/headphones.jpg",
        "createdAt": "2025-01-15T10:00:00Z",
    },
    {
        "id": "prod-002",
        "name": "Organic Ceylon Tea (100 bags)",
        "description": "Premium hand-picked Ceylon black tea from Nuwara Eliya estates",
        "price": 12.99,
        "category": "food",
        "stock": 500,
        "imageUrl": "/images/ceylon-tea.jpg",
        "createdAt": "2025-01-15T10:00:00Z",
    },
    {
        "id": "prod-003",
        "name": "USB-C Laptop Stand",
        "description": "Adjustable aluminium stand with integrated USB-C hub (HDMI, USB 3.0, PD charging)",
        "price": 49.99,
        "category": "electronics",
        "stock": 75,
        "imageUrl": "/images/laptop-stand.jpg",
        "createdAt": "2025-01-15T10:00:00Z",
    },
    {
        "id": "prod-004",
        "name": "Handloom Cotton Sarong",
        "description": "Traditional Sri Lankan handloom sarong, 100% cotton, machine washable",
        "price": 24.99,
        "category": "clothing",
        "stock": 200,
        "imageUrl": "/images/sarong.jpg",
        "createdAt": "2025-01-15T10:00:00Z",
    },
    {
        "id": "prod-005",
        "name": "Mechanical Keyboard (TKL)",
        "description": "Tenkeyless mechanical keyboard with Cherry MX Brown switches, RGB backlight",
        "price": 89.99,
        "category": "electronics",
        "stock": 60,
        "imageUrl": "/images/keyboard.jpg",
        "createdAt": "2025-01-15T10:00:00Z",
    },
    {
        "id": "prod-006",
        "name": "Coconut Oil (Cold Pressed, 500ml)",
        "description": "Virgin cold-pressed coconut oil from Southern Province, Sri Lanka",
        "price": 8.99,
        "category": "food",
        "stock": 300,
        "imageUrl": "/images/coconut-oil.jpg",
        "createdAt": "2025-01-15T10:00:00Z",
    },
]

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------
app = Flask(__name__)
CORS(app, origins=["http://localhost:3000", "http://localhost:80"]) # Allow frontend
app.config["JSON_SORT_KEYS"] = False

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("product-service")

# ---------------------------------------------------------------------------
# Data store abstraction
# ---------------------------------------------------------------------------

class DynamoDBStore:
    def __init__(self):
        self.table_name = os.environ.get("DYNAMODB_PRODUCTS_TABLE")
        if not self.table_name:
            raise ValueError("DYNAMODB_PRODUCTS_TABLE environment variable not set")

        self.dynamodb = boto3.resource("dynamodb")
        self.table = self.dynamodb.Table(self.table_name)
        self.migrate_to_dynamodb()
        logger.info(f"Initialized DynamoDB store for table: {self.table_name}")

    def migrate_to_dynamodb(self):
        table = self.dynamodb.Table(self.table_name)

        with table.batch_writer() as batch:
            for product in SEED_PRODUCTS:
                # Convert floats to Decimals
                product['price'] = Decimal(str(product['price']))
                batch.put_item(Item=product)
        print(f"Successfully migrated {len(SEED_PRODUCTS)} products to {self.table_name}")

    def _to_decimal(self, obj):
        if isinstance(obj, list):
            for i in range(len(obj)):
                obj[i] = self._to_decimal(obj[i])
            return obj
        elif isinstance(obj, dict):
            for k, v in obj.items():
                obj[k] = self._to_decimal(v)
            return obj
        elif isinstance(obj, float):
            return Decimal(str(obj))
        return obj

    def _from_decimal(self, obj):
        if isinstance(obj, list):
            for i in range(len(obj)):
                obj[i] = self._from_decimal(obj[i])
            return obj
        elif isinstance(obj, dict):
            for k, v in obj.items():
                obj[k] = self._from_decimal(v)
            return obj
        elif isinstance(obj, Decimal):
            return float(obj)
        return obj

    def get_all(self, category=None, search=None):
        try:
            response = self.table.scan()
            items = response.get("Items", [])
            # Handle pagination if necessary
            while "LastEvaluatedKey" in response:
                response = self.table.scan(ExclusiveStartKey=response["LastEvaluatedKey"])
                items.extend(response.get("Items", []))
            
            if category:
                items = [p for p in items if p.get("category") == category]
            if search:
                q = search.lower()
                items = [
                    p
                    for p in items
                    if q in str(p.get("name", "")).lower()
                    or q in str(p.get("description", "")).lower()
                ]

            return self._from_decimal(items)
        except ClientError as e:
            logger.error(f"DynamoDB scan failed: {e.response['Error']['Message']}")
            return []

    def get_by_id(self, product_id):
        try:
            response = self.table.get_item(Key={"id": product_id})
            item = response.get("Item")
            return self._from_decimal(item) if item else None
        except ClientError as e:
            logger.error(f"DynamoDB get_item failed: {e.response['Error']['Message']}")
            return None

    def create(self, product):
        try:
            product['createdAt'] = datetime.utcnow().isoformat() + "Z"
            item_to_create = self._to_decimal(product.copy())
            self.table.put_item(Item=item_to_create)
            logger.info(f"Product created: {product['id']}")
            return product
        except ClientError as e:
            logger.error(f"DynamoDB put_item failed: {e.response['Error']['Message']}")
            return None

    def update(self, product_id, updates):
        try:
            update_expression = "SET " + ", ".join(f"#{k}=:{k}" for k in updates)
            expression_attribute_names = {f"#{k}": k for k in updates}
            expression_attribute_values = self._to_decimal({f":{k}": v for k, v in updates.items()})

            response = self.table.update_item(
                Key={"id": product_id},
                UpdateExpression=update_expression,
                ExpressionAttributeNames=expression_attribute_names,
                ExpressionAttributeValues=expression_attribute_values,
                ReturnValues="ALL_NEW",
            )
            logger.info(f"Product updated: {product_id}")
            return self._from_decimal(response["Attributes"])
        except ClientError as e:
            logger.error(f"DynamoDB update_item failed: {e.response['Error']['Message']}")
            return None

    def check_stock(self, product_id, quantity):
        product = self.get_by_id(product_id)
        if not product:
            return False
        return int(product.get("stock", 0)) >= quantity

    def decrement_stock(self, product_id, quantity):
        from botocore.exceptions import ClientError

        try:
            self.table.update_item(
                Key={"id": product_id},
                UpdateExpression="SET stock = stock - :qty, updatedAt = :updated_at",
                ConditionExpression="attribute_exists(id) AND stock >= :qty",
                ExpressionAttributeValues={
                    ":qty": quantity,
                    ":updated_at": datetime.utcnow().isoformat() + "Z",
                },
                ReturnValues="UPDATED_NEW",
            )
            return True
        except ClientError as e:
            error_code = e.response.get("Error", {}).get("Code", "")
            if error_code == "ConditionalCheckFailedException":
                return False
            raise

# class InMemoryStore:
#     """Simple in-memory product store for local development."""

#     def __init__(self):
#         self.products = {p["id"]: dict(p) for p in SEED_PRODUCTS}

#     def get_all(self, category=None, search=None):
#         results = list(self.products.values())
#         if category:
#             results = [p for p in results if p["category"] == category]
#         if search:
#             q = search.lower()
#             results = [
#                 p
#                 for p in results
#                 if q in p["name"].lower() or q in p["description"].lower()
#             ]
#         return results

#     def get_by_id(self, product_id):
#         return self.products.get(product_id)

#     def create(self, data):
#         product_id = f"prod-{uuid.uuid4().hex[:6]}"
#         product = {
#             "id": product_id,
#             "name": data["name"],
#             "description": data.get("description", ""),
#             "price": float(data["price"]),
#             "category": data.get("category", "general"),
#             "stock": int(data.get("stock", 0)),
#             "imageUrl": data.get("imageUrl", ""),
#             "createdAt": datetime.utcnow().isoformat() + "Z",
#         }
#         self.products[product_id] = product
#         return product

#     def update(self, product_id, data):
#         if product_id not in self.products:
#             return None
#         product = self.products[product_id]
#         for key in ["name", "description", "price", "category", "stock", "imageUrl"]:
#             if key in data:
#                 product[key] = data[key]
#         product["updatedAt"] = datetime.utcnow().isoformat() + "Z"
#         return product

#     def delete(self, product_id):
#         return self.products.pop(product_id, None) is not None

#     def check_stock(self, product_id, quantity):
#         product = self.products.get(product_id)
#         if not product:
#             return False
#         return product["stock"] >= quantity

#     def decrement_stock(self, product_id, quantity):
#         product = self.products.get(product_id)
#         if product and product["stock"] >= quantity:
#             product["stock"] -= quantity
#             return True
#         return False


# ---------------------------------------------------------------------------
# Cloud store adapters (students implement these for the assignment)
# ---------------------------------------------------------------------------

# Use DynamoDB if the environment variable is set, otherwise fall back to in-memory
store_backend = os.environ.get("STORE_BACKEND")
if store_backend == "dynamodb":
    logger.info("Using DynamoDB store backend")
    store = DynamoDBStore()
else:
    logger.info("Using in-memory store backend (default)")
    store = InMemoryStore()


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.route("/health")
def health():
    """Health check endpoint for Kubernetes liveness/readiness probes."""
    return jsonify({"status": "healthy", "service": "product-service"})


@app.route("/ready")
def ready():
    """Readiness check — verifies the store is accessible."""
    try:
        store.get_all()
        return jsonify({"status": "ready", "service": "product-service"})
    except Exception as e:
        return jsonify({"status": "not ready", "error": str(e)}), 503


@app.route("/products", methods=["GET"])
def list_products():
    """
    List all products.
    Query params: ?category=electronics  &search=headphone
    """
    category = request.args.get("category")
    search = request.args.get("search")
    products = store.get_all(category=category, search=search)
    return jsonify({"products": products, "count": len(products)})


@app.route("/products/<product_id>", methods=["GET"])
def get_product(product_id):
    """Get a single product by ID."""
    product = store.get_by_id(product_id)
    if not product:
        abort(404, description=f"Product {product_id} not found")
    return jsonify(product)


@app.route("/products", methods=["POST"])
def create_product():
    """Create a new product."""
    data = request.get_json()
    if not data or "name" not in data or "price" not in data:
        abort(400, description="Missing required fields: name, price")
    product = store.create(data)
    logger.info(f"Created product: {product['id']} — {product['name']}")
    return jsonify(product), 201


@app.route("/products/<product_id>", methods=["PUT"])
def update_product(product_id):
    """Update an existing product."""
    data = request.get_json()
    if not data:
        abort(400, description="Request body required")
    product = store.update(product_id, data)
    if not product:
        abort(404, description=f"Product {product_id} not found")
    logger.info(f"Updated product: {product_id}")
    return jsonify(product)


@app.route("/products/<product_id>", methods=["DELETE"])
def delete_product(product_id):
    """Delete a product."""
    if not store.delete(product_id):
        abort(404, description=f"Product {product_id} not found")
    logger.info(f"Deleted product: {product_id}")
    return jsonify({"message": f"Product {product_id} deleted"}), 200


@app.route("/products/<product_id>/stock", methods=["GET"])
def check_stock(product_id):
    """Check stock availability (called by order-service)."""
    product = store.get_by_id(product_id)
    if not product:
        abort(404, description=f"Product {product_id} not found")
    return jsonify(
        {"productId": product_id, "stock": product["stock"], "available": product["stock"] > 0}
    )


@app.route("/products/<product_id>/stock/decrement", methods=["POST"])
def decrement_stock(product_id):
    """Decrement stock after order placement (called by order-service)."""
    data = request.get_json() or {}
    quantity = int(data.get("quantity", 1))
    if not store.decrement_stock(product_id, quantity):
        abort(409, description=f"Insufficient stock for product {product_id}")
    logger.info(f"Decremented stock for {product_id} by {quantity}")
    return jsonify({"message": "Stock updated", "productId": product_id})


@app.route("/categories", methods=["GET"])
def list_categories():
    """List all unique product categories."""
    products = store.get_all()
    categories = sorted(set(p["category"] for p in products))
    return jsonify({"categories": categories})


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
    logger.error(f"Internal Server Error: {e}")
    return jsonify({"error": "Internal Server Error"}), 500


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8001))
    debug = os.environ.get("FLASK_DEBUG", "false").lower() == "true"
    logger.info(f"Starting product-service on port {port}")
    app.run(host="0.0.0.0", port=port, debug=debug)
