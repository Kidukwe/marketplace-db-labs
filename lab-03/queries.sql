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
