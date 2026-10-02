TRUNCATE TABLE users RESTART IDENTITY CASCADE;

INSERT INTO users (full_name, email, phone)
VALUES
    ('Иван Продавцов', 'seller@example.com', '+79990000001'),
    ('Анна Покупатель', 'buyer@example.com', '+79990000002');

INSERT INTO sellers (user_id, store_name, description)
VALUES
    (1, 'Tech Store', 'Магазин электроники');

INSERT INTO categories (parent_id, name)
VALUES
    (NULL, 'Электроника'),
    (1, 'Смартфоны');

INSERT INTO products (seller_id, category_id, title, description, price)
VALUES
    (1, 2, 'Smartphone X', 'Тестовый смартфон', 59990.00);

INSERT INTO stock (product_id, quantity)
VALUES
    (1, 25);

INSERT INTO carts (user_id)
VALUES
    (2);

INSERT INTO cart_items (cart_id, product_id, quantity)
VALUES
    (1, 1, 2);

INSERT INTO addresses (user_id, city, street, house, apartment)
VALUES
    (2, 'Москва', 'Тверская', '10', '15');

INSERT INTO orders (user_id)
VALUES
    (2);

INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES
    (1, 1, 1, 59990.00);

INSERT INTO payments (order_id, amount, status, paid_at)
VALUES
    (1, 59990.00, 'completed', now());

INSERT INTO deliveries (order_id, address_id, delivery_status)
VALUES
    (1, 1, 'processing');

INSERT INTO reviews (user_id, product_id, score, comment)
VALUES
    (2, 1, 4, 'Хороший смартфон'),
    (2, 1, 5, 'После обновления стал работать лучше');