-- ЛР4. Только чтение существующих таблиц public ЛР1–ЛР2.
-- Оплаченные продажи: payments.status = completed.
-- День заказа по Europe/Moscow, сумма позиций по исторической unit_price.

-- Q01. Рейтинг товаров по цене внутри категории.
SELECT p.id, p.category_id, c.name AS category, p.title, p.price,
       ROW_NUMBER() OVER (
           PARTITION BY p.category_id ORDER BY p.price DESC, p.id
       ) AS row_num,
       RANK() OVER w AS price_rank,
       DENSE_RANK() OVER w AS dense_price_rank
FROM public.products AS p
JOIN public.categories AS c ON c.id = p.category_id
WINDOW w AS (PARTITION BY p.category_id ORDER BY p.price DESC)
ORDER BY p.category_id, p.price DESC, p.id;

-- Q02. Три самых дорогих товара каждой категории через CTE.
WITH ranked_products AS (
    SELECT p.id, p.category_id, p.title, p.price,
           ROW_NUMBER() OVER (
               PARTITION BY p.category_id ORDER BY p.price DESC, p.id
           ) AS row_num
    FROM public.products AS p
)
SELECT r.category_id, c.name AS category, r.id, r.title, r.price, r.row_num
FROM ranked_products AS r
JOIN public.categories AS c ON c.id = r.category_id
WHERE r.row_num <= 3
ORDER BY r.category_id, r.row_num;

-- Q03. Нарастающий итог оплаченных продаж по календарным дням.
WITH day_sales AS (
    SELECT (o.created_at AT TIME ZONE 'Europe/Moscow')::date AS day,
           SUM(oi.quantity * oi.unit_price) AS day_revenue
    FROM public.orders AS o
    JOIN public.order_items AS oi ON oi.order_id = o.id
    WHERE EXISTS (
        SELECT 1 FROM public.payments AS pay
        WHERE pay.order_id = o.id AND pay.status = 'completed'
    )
    GROUP BY (o.created_at AT TIME ZONE 'Europe/Moscow')::date
), calendar AS (
    SELECT g.day::date AS day
    FROM generate_series(
        (SELECT MIN(day)::timestamp FROM day_sales),
        (SELECT MAX(day)::timestamp FROM day_sales),
        INTERVAL '1 day'
    ) AS g(day)
), daily AS (
    SELECT c.day, COALESCE(s.day_revenue, 0::numeric) AS day_revenue
    FROM calendar AS c
    LEFT JOIN day_sales AS s ON s.day = c.day
)
SELECT day, day_revenue,
       SUM(day_revenue) OVER (
           ORDER BY day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_revenue
FROM daily
ORDER BY day;

-- Q04. Доля продавца в оплаченных продажах категории.
WITH seller_category_sales AS (
    SELECT p.category_id, p.seller_id,
           SUM(oi.quantity * oi.unit_price) AS seller_revenue
    FROM public.order_items AS oi
    JOIN public.products AS p ON p.id = oi.product_id
    WHERE EXISTS (
        SELECT 1 FROM public.payments AS pay
        WHERE pay.order_id = oi.order_id AND pay.status = 'completed'
    )
    GROUP BY p.category_id, p.seller_id
), shares AS (
    SELECT *, SUM(seller_revenue) OVER (
        PARTITION BY category_id
    ) AS category_revenue
    FROM seller_category_sales
)
SELECT x.category_id, c.name AS category, x.seller_id, s.store_name,
       x.seller_revenue, x.category_revenue,
       x.seller_revenue / NULLIF(x.category_revenue, 0) AS revenue_share,
       ROUND(100 * x.seller_revenue / NULLIF(x.category_revenue, 0), 2)
           AS revenue_share_pct
FROM shares AS x
JOIN public.categories AS c ON c.id = x.category_id
JOIN public.sellers AS s ON s.id = x.seller_id
ORDER BY x.category_id, x.seller_revenue DESC, x.seller_id;

-- Q05. LAG и LEAD и изменение дневной выручки.
WITH day_sales AS (
    SELECT (o.created_at AT TIME ZONE 'Europe/Moscow')::date AS day,
           SUM(oi.quantity * oi.unit_price) AS day_revenue
    FROM public.orders AS o
    JOIN public.order_items AS oi ON oi.order_id = o.id
    WHERE EXISTS (
        SELECT 1 FROM public.payments AS pay
        WHERE pay.order_id = o.id AND pay.status = 'completed'
    )
    GROUP BY (o.created_at AT TIME ZONE 'Europe/Moscow')::date
), calendar AS (
    SELECT g.day::date AS day
    FROM generate_series(
        (SELECT MIN(day)::timestamp FROM day_sales),
        (SELECT MAX(day)::timestamp FROM day_sales),
        INTERVAL '1 day'
    ) AS g(day)
), daily AS (
    SELECT c.day, COALESCE(s.day_revenue, 0::numeric) AS day_revenue
    FROM calendar AS c
    LEFT JOIN day_sales AS s ON s.day = c.day
), neighbors AS (
    SELECT day, day_revenue,
           LAG(day_revenue) OVER (ORDER BY day) AS prev_day_revenue,
           LEAD(day_revenue) OVER (ORDER BY day) AS next_day_revenue
    FROM daily
)
SELECT day, day_revenue, prev_day_revenue, next_day_revenue,
       day_revenue - prev_day_revenue AS revenue_growth,
       ROUND(100 * (day_revenue - prev_day_revenue)
           / NULLIF(prev_day_revenue, 0), 2) AS growth_pct,
       next_day_revenue - day_revenue AS next_day_growth
FROM neighbors
ORDER BY day;

-- Q06. Средняя цена категории рядом с каждым товаром оконным способом.
SELECT p.id, p.category_id, p.title, p.price,
       AVG(p.price) OVER (PARTITION BY p.category_id) AS category_avg_price,
       p.price - AVG(p.price) OVER (PARTITION BY p.category_id) AS price_delta
FROM public.products AS p
ORDER BY p.category_id, p.id;

-- Q07. Та же задача обычной группировкой с обратным JOIN.
WITH category_averages AS (
    SELECT category_id, AVG(price) AS category_avg_price
    FROM public.products
    GROUP BY category_id
)
SELECT p.id, p.category_id, p.title, p.price,
       a.category_avg_price, p.price - a.category_avg_price AS price_delta
FROM public.products AS p
JOIN category_averages AS a ON a.category_id = p.category_id
ORDER BY p.category_id, p.id;

-- Q08. Дополнительно сравнение рамок ROWS и RANGE при равных ценах.
SELECT p.id, p.category_id, p.title, p.price,
       SUM(p.price) OVER (
           PARTITION BY p.category_id ORDER BY p.price DESC, p.id
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS rows_total,
       SUM(p.price) OVER (
           PARTITION BY p.category_id ORDER BY p.price DESC
           RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS range_total
FROM public.products AS p
ORDER BY p.category_id, p.price DESC, p.id;
