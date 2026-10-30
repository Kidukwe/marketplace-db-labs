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
