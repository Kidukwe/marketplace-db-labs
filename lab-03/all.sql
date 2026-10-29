-- ЛР3. Полный запуск: запросы → два VIEW → проверки.
-- Требуется уже заполненная база ЛР1–ЛР2. Таблицы не пересоздаются.

-- ЛР3. SELECT-запросы к существующим таблицам public из ЛР1–ЛР2.
-- Не изменяют данные. Каждый блок можно запускать отдельно в DBeaver.

-- Q01. INNER JOIN трёх таблиц: товар — категория — продавец.
SELECT p.title, c.name AS category, s.store_name AS seller
FROM public.products AS p
INNER JOIN public.sellers AS s ON p.seller_id = s.id
INNER JOIN public.categories AS c ON c.id = p.category_id
ORDER BY p.id;

-- Q02. LEFT JOIN: товары, у которых нет ни одного отзыва.
SELECT p.id, p.title
FROM public.products AS p
LEFT JOIN public.reviews AS r ON p.id = r.product_id
WHERE r.id IS NULL
ORDER BY p.id;

-- Q03. Все категории, включая пустые: количество товаров и средняя цена.
-- COUNT(p.id), а не COUNT(*): пустая категория должна иметь 0 товаров.
SELECT c.id AS category_id, c.name AS category,
       COUNT(p.id) AS products_count,
       ROUND(AVG(p.price), 2) AS avg_price
FROM public.categories AS c
LEFT JOIN public.products AS p ON p.category_id = c.id
GROUP BY c.id, c.name
ORDER BY products_count DESC, c.id;

-- Q04. HAVING: категории, в которых больше 100 товаров.
-- Это написанный в учебном режиме запрос; WHERE не заменяет HAVING.
SELECT c.name AS category, COUNT(*) AS products_count,
       AVG(p.price) AS avg_price
FROM public.products AS p
INNER JOIN public.categories AS c ON p.category_id = c.id
GROUP BY c.id, c.name
HAVING COUNT(*) > 100
ORDER BY products_count DESC, c.id;

-- Q05. Скалярный подзапрос: товары дороже общей средней цены.
SELECT p.id, p.title, p.price
FROM public.products AS p
WHERE p.price > (
    SELECT AVG(p2.price) AS avg_price
    FROM public.products AS p2
)
ORDER BY p.price DESC, p.id;

-- Q06. IN: товары из категорий с названием, начинающимся на «ЛР2:».
SELECT p.id, p.title, p.category_id
FROM public.products AS p
WHERE p.category_id IN (
    SELECT c.id
    FROM public.categories AS c
    WHERE c.name LIKE 'ЛР2:%'
)
ORDER BY p.id;

-- Q07. Коррелированный EXISTS: продавцы, у которых есть товары.
-- SELECT 1 не считает товары: EXISTS проверяет наличие хотя бы одной строки.
SELECT s.id, s.store_name
FROM public.sellers AS s
WHERE EXISTS (
    SELECT 1
    FROM public.products AS p
    WHERE p.seller_id = s.id
)
ORDER BY s.id;

-- Q08. CTE: оплаченные позиции → сумма продаж по продавцам → отчёт.
-- Оплаченная продажа здесь: есть payments.status = 'completed'.
-- Берём историческую unit_price, а не текущую products.price.
WITH paid_items AS (
    SELECT p.seller_id, oi.order_id, oi.quantity, oi.unit_price
    FROM public.order_items AS oi
    JOIN public.products AS p ON p.id = oi.product_id
    WHERE EXISTS (
        SELECT 1 FROM public.payments AS pay
        WHERE pay.order_id = oi.order_id AND pay.status = 'completed'
    )
), seller_totals AS (
    SELECT seller_id, COUNT(DISTINCT order_id) AS paid_orders_count,
           SUM(quantity) AS units_sold,
           SUM(quantity * unit_price) AS paid_sales_amount
    FROM paid_items
    GROUP BY seller_id
)
SELECT s.id AS seller_id, s.store_name,
       t.paid_orders_count, t.units_sold, t.paid_sales_amount
FROM seller_totals AS t
JOIN public.sellers AS s ON s.id = t.seller_id
ORDER BY t.paid_sales_amount DESC, s.id;

-- Q09. Рекурсивный CTE: дерево категорий от всех корней до потомков.
-- Для одного дерева можно добавить в начальный SELECT: AND c.name = 'ЛР2: Каталог'.
-- path_ids хранит посещённые id и предотвращает зацикливание в текущем пути.
WITH RECURSIVE category_tree AS (
    SELECT c.id, c.parent_id, c.name, 0 AS depth,
           ARRAY[c.id] AS path_ids, c.name::text AS category_path
    FROM public.categories AS c
    WHERE c.parent_id IS NULL
    UNION ALL
    SELECT child.id, child.parent_id, child.name, tree.depth + 1,
           tree.path_ids || child.id,
           tree.category_path || ' / ' || child.name
    FROM public.categories AS child
    JOIN category_tree AS tree ON child.parent_id = tree.id
    WHERE NOT (child.id = ANY(tree.path_ids))
)
SELECT id, parent_id, name, depth, category_path
FROM category_tree
ORDER BY path_ids;


-- ЛР3. Два обычных представления. Таблицы и строки ЛР1–ЛР2 сохраняются.
-- Повторный запуск обновляет определения только этих представлений ЛР3.
BEGIN;

-- V01. Каталог с названием категории и магазина.
CREATE OR REPLACE VIEW public.lr3_product_catalog AS
SELECT p.id AS product_id, p.title, p.price, p.is_active,
       c.id AS category_id, c.name AS category,
       s.id AS seller_id, s.store_name AS seller
FROM public.products AS p
JOIN public.categories AS c ON c.id = p.category_id
JOIN public.sellers AS s ON s.id = p.seller_id;

-- V02. Продавцы, включая тех, у кого нет товаров или оплаченных продаж.
-- Две независимые агрегации предотвращают размножение количества товаров
-- при соединении с несколькими позициями заказов.
CREATE OR REPLACE VIEW public.lr3_seller_report AS
WITH product_totals AS (
    SELECT seller_id, COUNT(*) AS products_count
    FROM public.products
    GROUP BY seller_id
), paid_sales AS (
    SELECT p.seller_id, COUNT(DISTINCT oi.order_id) AS paid_orders_count,
           SUM(oi.quantity) AS units_sold,
           SUM(oi.quantity * oi.unit_price) AS paid_sales_amount
    FROM public.order_items AS oi
    JOIN public.products AS p ON p.id = oi.product_id
    WHERE EXISTS (
        SELECT 1 FROM public.payments AS pay
        WHERE pay.order_id = oi.order_id AND pay.status = 'completed'
    )
    GROUP BY p.seller_id
)
SELECT s.id AS seller_id, s.store_name,
       COALESCE(pt.products_count, 0::bigint) AS products_count,
       COALESCE(ps.paid_orders_count, 0::bigint) AS paid_orders_count,
       COALESCE(ps.units_sold, 0::bigint) AS units_sold,
       COALESCE(ps.paid_sales_amount, 0::numeric) AS paid_sales_amount
FROM public.sellers AS s
LEFT JOIN product_totals AS pt ON pt.seller_id = s.id
LEFT JOIN paid_sales AS ps ON ps.seller_id = s.id;

COMMIT;

-- Q10. Обращение к первому VIEW: активный каталог.
SELECT product_id, title, category, seller, price
FROM public.lr3_product_catalog
WHERE is_active
ORDER BY price DESC, product_id
LIMIT 20;

-- Q11. Обращение ко второму VIEW: отчёт по всем продавцам.
SELECT seller_id, store_name, products_count,
       paid_orders_count, units_sold, paid_sales_amount
FROM public.lr3_seller_report
ORDER BY paid_sales_amount DESC, seller_id;


-- Проверки результата ЛР3. Данные не изменяются.
DO $$
BEGIN
    IF (SELECT COUNT(*) FROM public.lr3_product_catalog)
       <> (SELECT COUNT(*) FROM public.products) THEN
        RAISE EXCEPTION 'Каталог потерял или размножил товары';
    END IF;
    IF (SELECT COUNT(*) FROM public.lr3_seller_report)
       <> (SELECT COUNT(*) FROM public.sellers) THEN
        RAISE EXCEPTION 'Отчёт потерял или размножил продавцов';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.lr3_seller_report AS r
        WHERE r.products_count <> (
            SELECT COUNT(*) FROM public.products AS p WHERE p.seller_id = r.seller_id
        )
    ) THEN
        RAISE EXCEPTION 'Неверное количество товаров продавца';
    END IF;
    -- Общая сумма в отчёте равна стоимости позиций оплаченных заказов.
    IF (SELECT COALESCE(SUM(paid_sales_amount), 0) FROM public.lr3_seller_report)
       IS DISTINCT FROM (
           SELECT COALESCE(SUM(oi.quantity * oi.unit_price), 0)
           FROM public.order_items AS oi
           JOIN public.payments AS pay ON pay.order_id = oi.order_id
           WHERE pay.status = 'completed'
       ) THEN
        RAISE EXCEPTION 'Неверная общая сумма оплаченных продаж';
    END IF;
    -- Два способа найти товары без отзывов должны давать одинаковые id.
    IF EXISTS (
        (SELECT p.id FROM public.products AS p
         LEFT JOIN public.reviews AS r ON r.product_id = p.id
         WHERE r.id IS NULL
         EXCEPT
         SELECT p.id FROM public.products AS p
         WHERE NOT EXISTS (SELECT 1 FROM public.reviews AS r WHERE r.product_id = p.id))
        UNION ALL
        (SELECT p.id FROM public.products AS p
         WHERE NOT EXISTS (SELECT 1 FROM public.reviews AS r WHERE r.product_id = p.id)
         EXCEPT
         SELECT p.id FROM public.products AS p
         LEFT JOIN public.reviews AS r ON r.product_id = p.id
         WHERE r.id IS NULL)
    ) THEN
        RAISE EXCEPTION 'LEFT JOIN и NOT EXISTS дали разные наборы';
    END IF;
    RAISE NOTICE 'Проверки лабораторной №3 пройдены';
END $$;
