-- ЛР2. Только наполнение таблиц public, созданных в лабораторной №1.
-- Выполнять целиком. Существующие строки сохраняются.
-- Данные ЛР2 отмечены префиксом «ЛР2» и отдельными email.
-- При ошибке выполнить ROLLBACK перед повторным запуском.
BEGIN;

-- 1. Два учебных пользователя. Email — существующий уникальный ключ.
INSERT INTO public.users (full_name, email, created_at)
VALUES ('ЛР2 Продавец', 'seller@lr2.example.test', '2026-02-01 09:00:00+03'),
       ('ЛР2 Покупатель', 'buyer@lr2.example.test', '2026-02-01 09:00:00+03')
ON CONFLICT (email) DO NOTHING;

INSERT INTO public.sellers (user_id, store_name, description, created_at)
SELECT id, 'ЛР2 Магазин', 'Магазин для тестовых данных лабораторной №2',
       TIMESTAMPTZ '2026-02-01 09:00:00+03'
FROM public.users WHERE email = 'seller@lr2.example.test'
ON CONFLICT (user_id) DO NOTHING;

-- Категории дополняют существующие; таблица categories не пересоздаётся.
INSERT INTO public.categories (name) VALUES ('ЛР2: Каталог')
ON CONFLICT (name) DO NOTHING;

INSERT INTO public.categories (parent_id, name)
SELECT root.id, 'ЛР2: ' || g.name
FROM public.categories AS root
CROSS JOIN (VALUES ('Смартфоны'), ('Ноутбуки'), ('Книги'), ('Одежда'), ('Аксессуары')) AS g(name)
WHERE root.name = 'ЛР2: Каталог'
ON CONFLICT (name) DO NOTHING;

-- 2. 1200 товаров. Формулы не опираются на значения IDENTITY.
-- Проверка названия предотвращает повторное добавление учебной партии.
-- Схема допускает одинаковые названия вообще: префикс ЛР2 зарезервирован
-- для этой партии; запуск последовательный, без параллельного наполнения.
INSERT INTO public.products
    (seller_id, category_id, title, price, is_active, description, created_at)
SELECT s.id, c.id,
       'ЛР2 ' || (ARRAY['Смартфон', 'Ноутбук', 'Книга', 'Куртка', 'Чехол'])[n % 5 + 1] || ' №' || n,
       (500 + (n % 100) * 500)::numeric(12, 2),
       n % 4 <> 0,
       CASE WHEN n % 7 = 0 THEN NULL ELSE 'ЛР2 Описание товара №' || n END,
       TIMESTAMPTZ '2026-03-01 09:00:00+03' + n * INTERVAL '1 minute'
FROM generate_series(0, 1199) AS g(n)
JOIN public.sellers AS s ON s.store_name = 'ЛР2 Магазин'
JOIN public.categories AS c
    ON c.name = 'ЛР2: ' || (ARRAY['Смартфоны', 'Ноутбуки', 'Книги', 'Одежда', 'Аксессуары'])[n % 5 + 1]
WHERE NOT EXISTS (
    SELECT 1 FROM public.products AS p
    WHERE p.title = 'ЛР2 ' || (ARRAY['Смартфон', 'Ноутбук', 'Книга', 'Куртка', 'Чехол'])[n % 5 + 1] || ' №' || n
);

-- Добавляем недостающие остатки и для ранее добавленных вручную товаров.
-- Уже существующие остатки не изменяются.
INSERT INTO public.stock (product_id, quantity, updated_at)
SELECT id, (id * 7) % 101, TIMESTAMPTZ '2026-10-01 09:00:00+03'
FROM public.products AS p
WHERE NOT EXISTS (SELECT 1 FROM public.stock AS s WHERE s.product_id = p.id);

-- 3. Корзина и адрес учебного покупателя.
INSERT INTO public.carts (user_id, created_at)
SELECT id, TIMESTAMPTZ '2026-03-01 09:00:00+03'
FROM public.users WHERE email = 'buyer@lr2.example.test'
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.cart_items (cart_id, product_id, quantity)
SELECT c.id, p.id, 1
FROM public.carts AS c
JOIN public.users AS u ON u.id = c.user_id
CROSS JOIN public.products AS p
WHERE u.email = 'buyer@lr2.example.test'
  AND p.title IN ('ЛР2 Смартфон №0', 'ЛР2 Ноутбук №1', 'ЛР2 Книга №2')
ON CONFLICT (cart_id, product_id) DO NOTHING;

INSERT INTO public.addresses (user_id, city, street, house, apartment, created_at)
SELECT u.id, 'Москва', 'Учебная ЛР2', '10', '15',
       TIMESTAMPTZ '2026-03-01 09:00:00+03'
FROM public.users AS u
WHERE u.email = 'buyer@lr2.example.test'
  AND NOT EXISTS (
      SELECT 1 FROM public.addresses AS a
      WHERE a.user_id = u.id AND a.street = 'Учебная ЛР2' AND a.house = '10'
  );

-- 4. 1200 заказов и связанные данные.
-- DO — вспомогательный блок генератора, не функция и не новая таблица.
-- В цикле работаем с фактическими ID. RETURNING получает ID нового заказа.
-- Для повторного запуска заказ узнаём по учебному покупателю и фиксированной дате.
DO $$
DECLARE
    n integer;
    k integer;
    product_number integer;
    buyer_id bigint;
    address_key bigint;
    order_key bigint;
    product_key bigint;
    first_product_key bigint;
    product_price numeric(12, 2);
    order_date timestamptz;
    order_status text;
BEGIN
    SELECT id INTO STRICT buyer_id FROM public.users WHERE email = 'buyer@lr2.example.test';
    SELECT id INTO STRICT address_key FROM public.addresses
    WHERE user_id = buyer_id AND street = 'Учебная ЛР2' AND house = '10';

    FOR n IN 0..1199 LOOP
        order_date := TIMESTAMPTZ '2026-09-01 09:00:00+03' + n * INTERVAL '30 minutes';
        order_status := (ARRAY['pending', 'paid', 'shipped', 'delivered'])[n % 4 + 1];
        SELECT id INTO order_key FROM public.orders
        WHERE user_id = buyer_id AND created_at = order_date;
        IF NOT FOUND THEN
            INSERT INTO public.orders (user_id, status, created_at)
            VALUES (buyer_id, order_status, order_date)
            RETURNING id INTO order_key;
        END IF;

        FOR k IN 0..1 LOOP
            product_number := (n * 2 + k) % 1200;
            SELECT id, price INTO STRICT product_key, product_price
            FROM public.products
            WHERE title = 'ЛР2 ' || (ARRAY['Смартфон', 'Ноутбук', 'Книга', 'Куртка', 'Чехол'])[product_number % 5 + 1]
                          || ' №' || product_number;
            IF k = 0 THEN first_product_key := product_key; END IF;
            INSERT INTO public.order_items (order_id, product_id, quantity, unit_price)
            VALUES (order_key, product_key, k + 1, product_price)
            ON CONFLICT (order_id, product_id) DO NOTHING;
        END LOOP;

        IF order_status <> 'pending' THEN
            INSERT INTO public.payments (order_id, amount, status, paid_at)
            SELECT order_key, SUM(quantity * unit_price), 'completed', order_date + INTERVAL '5 minutes'
            FROM public.order_items WHERE order_id = order_key
            ON CONFLICT (order_id) DO NOTHING;
        END IF;

        IF order_status IN ('shipped', 'delivered') THEN
            INSERT INTO public.deliveries (order_id, address_id, delivery_status, delivery_date)
            VALUES (order_key, address_key, order_status, order_date + INTERVAL '3 days')
            ON CONFLICT (order_id) DO NOTHING;
        END IF;

        IF order_status = 'delivered' THEN
            INSERT INTO public.reviews (user_id, product_id, score, comment, created_at)
            SELECT buyer_id, first_product_key, 1 + n % 5,
                   'ЛР2 Отзыв о заказе №' || n, order_date + INTERVAL '4 days'
            WHERE NOT EXISTS (
                SELECT 1 FROM public.reviews
                WHERE user_id = buyer_id AND comment = 'ЛР2 Отзыв о заказе №' || n
            );
        END IF;
    END LOOP;
END $$;

COMMIT;
