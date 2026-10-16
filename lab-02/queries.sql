-- ЛР2. Выборки из существующих таблиц public первой лабораторной.
-- Q01 проверяет общие количества. Q02–Q12 демонстрируют новую партию ЛР2,
-- чтобы результаты не зависели от количества предыдущих упражнений.

-- Q01. Количество строк во всех 13 таблицах (включая старые данные).
SELECT 'users' AS table_name, COUNT(*) AS row_count FROM public.users
UNION ALL SELECT 'sellers', COUNT(*) FROM public.sellers
UNION ALL SELECT 'categories', COUNT(*) FROM public.categories
UNION ALL SELECT 'products', COUNT(*) FROM public.products
UNION ALL SELECT 'stock', COUNT(*) FROM public.stock
UNION ALL SELECT 'carts', COUNT(*) FROM public.carts
UNION ALL SELECT 'cart_items', COUNT(*) FROM public.cart_items
UNION ALL SELECT 'addresses', COUNT(*) FROM public.addresses
UNION ALL SELECT 'orders', COUNT(*) FROM public.orders
UNION ALL SELECT 'order_items', COUNT(*) FROM public.order_items
UNION ALL SELECT 'payments', COUNT(*) FROM public.payments
UNION ALL SELECT 'deliveries', COUNT(*) FROM public.deliveries
UNION ALL SELECT 'reviews', COUNT(*) FROM public.reviews
ORDER BY table_name;

-- Q02. DISTINCT и псевдонимы: уникальные сочетания цены и активности товаров.
-- id не включаем: уникальный id сделал бы все строки различными.
SELECT DISTINCT price AS product_price, is_active AS active
FROM public.products
WHERE title LIKE 'ЛР2 %'
ORDER BY product_price ASC, active ASC;

-- Q03. AND, OR и скобки: активные недорогие смартфоны или дорогие ноутбуки.
SELECT id, title, price, is_active
FROM public.products
WHERE is_active
  AND ((title LIKE 'ЛР2 Смартфон №%' AND price <= 5000)
       OR (title LIKE 'ЛР2 Ноутбук №%' AND price >= 40000))
ORDER BY id
LIMIT 10;

-- Q04. BETWEEN включает обе границы: товары от 1000 до 2000 включительно.
SELECT id, title, price
FROM public.products
WHERE title LIKE 'ЛР2 %' AND price BETWEEN 1000 AND 2000
ORDER BY price ASC, id ASC
LIMIT 10;

-- Q05. IN: товары с одной из перечисленных цен.
SELECT id, title, price
FROM public.products
WHERE title LIKE 'ЛР2 %' AND price IN (500, 1000, 1500)
ORDER BY id
LIMIT 10;

-- Q06. ILIKE: поиск по части названия без учёта регистра.
SELECT id, title, price
FROM public.products
WHERE title ILIKE 'ЛР2 %СМАРТФОН%'
ORDER BY id
LIMIT 10;

-- Q07. LIKE: символ _ соответствует ровно одному символу.
SELECT id, title
FROM public.products
WHERE title LIKE 'ЛР2 Книга №_'
ORDER BY id;

-- Q08. IS NULL: товары без описания. COALESCE оформляет результат для чтения.
SELECT id, title, COALESCE(description, 'Нет описания') AS description
FROM public.products
WHERE title LIKE 'ЛР2 %' AND description IS NULL
ORDER BY id
LIMIT 10;

-- Q09. Два столбца в разных направлениях: цена убывает, id возрастает.
SELECT id, title, price
FROM public.products
WHERE title LIKE 'ЛР2 %'
ORDER BY price DESC, id ASC
LIMIT 10;

-- Q10. Первая страница по 10 товаров.
SELECT id, title, price
FROM public.products
WHERE title LIKE 'ЛР2 %'
ORDER BY price DESC, id ASC
LIMIT 10 OFFSET 0;

-- Q11. Вторая страница: пропускаем первые 10 товаров в том же порядке.
SELECT id, title, price
FROM public.products
WHERE title LIKE 'ЛР2 %'
ORDER BY price DESC, id ASC
LIMIT 10 OFFSET 10;

-- Q12. Положение NULL при сортировке, дополнительный пример к вопросу 7.
SELECT id, title, description
FROM public.products
WHERE title LIKE 'ЛР2 %'
ORDER BY description ASC NULLS FIRST, id ASC
LIMIT 10;
