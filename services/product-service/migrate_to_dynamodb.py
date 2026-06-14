import os
import boto3
from decimal import Decimal

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

def migrate_to_dynamodb():
    table_name = os.environ.get("DYNAMODB_PRODUCTS_TABLE")
    if not table_name:
        raise ValueError("DYNAMODB_PRODUCTS_TABLE environment variable not set")

    dynamodb = boto3.resource("dynamodb")
    table = dynamodb.Table(table_name)

    with table.batch_writer() as batch:
        for product in SEED_PRODUCTS:
            # Convert floats to Decimals
            product['price'] = Decimal(str(product['price']))
            batch.put_item(Item=product)

    print(f"Successfully migrated {len(SEED_PRODUCTS)} products to {table_name}")

if __name__ == "__main__":
    migrate_to_dynamodb()
