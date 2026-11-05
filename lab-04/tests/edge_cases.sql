-- Только для отдельной тестовой базы. Все строки фикстур откатываются.
BEGIN;
DO $$
DECLARE u1 bigint; u2 bigint; s1 bigint; s2 bigint; c bigint; empty_c bigint;
        a bigint; b bigint; z bigint; ord bigint;
BEGIN
 INSERT INTO public.users(full_name,email) VALUES ('ЛР4 тест 1','lr4-1@example.test') RETURNING id INTO u1;
 INSERT INTO public.users(full_name,email) VALUES ('ЛР4 тест 2','lr4-2@example.test') RETURNING id INTO u2;
 INSERT INTO public.sellers(user_id,store_name) VALUES(u1,'ЛР4 тест 1') RETURNING id INTO s1;
 INSERT INTO public.sellers(user_id,store_name) VALUES(u2,'ЛР4 тест 2') RETURNING id INTO s2;
 INSERT INTO public.categories(name) VALUES('ЛР4 тест цены') RETURNING id INTO c;
 INSERT INTO public.categories(name) VALUES('ЛР4 пустая') RETURNING id INTO empty_c;
 INSERT INTO public.products(seller_id,category_id,title,price) VALUES(s1,c,'ЛР4 A',100) RETURNING id INTO a;
 INSERT INTO public.products(seller_id,category_id,title,price) VALUES(s1,c,'ЛР4 B',100) RETURNING id INTO b;
 INSERT INTO public.products(seller_id,category_id,title,price) VALUES(s2,c,'ЛР4 C',50) RETURNING id INTO z;
 INSERT INTO public.orders(user_id,created_at) VALUES(u1,'2027-01-01 12:00:00+03') RETURNING id INTO ord;
 INSERT INTO public.order_items VALUES(ord,a,1,150),(ord,b,1,50);
 INSERT INTO public.payments(order_id,amount,status) VALUES(ord,200,'completed');
 INSERT INTO public.orders(user_id,created_at) VALUES(u1,'2027-01-03 12:00:00+03') RETURNING id INTO ord;
 INSERT INTO public.order_items VALUES(ord,z,1,50);
 INSERT INTO public.payments(order_id,amount,status) VALUES(ord,50,'completed');
 INSERT INTO public.orders(user_id,created_at) VALUES(u1,'2027-01-02 12:00:00+03') RETURNING id INTO ord;
 INSERT INTO public.order_items VALUES(ord,a,1,999);
 INSERT INTO public.payments(order_id,amount,status) VALUES(ord,999,'pending');
END $$;
DO $$
BEGIN
 IF (WITH actual AS (SELECT p.id, p.category_id, c.name AS category, p.title, p.price,
       ROW_NUMBER() OVER (
           PARTITION BY p.category_id ORDER BY p.price DESC, p.id
       ) AS row_num,
       RANK() OVER w AS price_rank,
       DENSE_RANK() OVER w AS dense_price_rank
FROM public.products AS p
JOIN public.categories AS c ON c.id = p.category_id
WINDOW w AS (PARTITION BY p.category_id ORDER BY p.price DESC)
ORDER BY p.category_id, p.price DESC, p.id) SELECT ((SELECT array_agg(price_rank ORDER BY row_num) FROM actual WHERE category='ЛР4 тест цены') IS DISTINCT FROM ARRAY[1,1,3]::bigint[])) THEN RAISE EXCEPTION 'RANK должен дать 1 1 3'; END IF;
 IF (WITH actual AS (SELECT p.id, p.category_id, c.name AS category, p.title, p.price,
       ROW_NUMBER() OVER (
           PARTITION BY p.category_id ORDER BY p.price DESC, p.id
       ) AS row_num,
       RANK() OVER w AS price_rank,
       DENSE_RANK() OVER w AS dense_price_rank
FROM public.products AS p
JOIN public.categories AS c ON c.id = p.category_id
WINDOW w AS (PARTITION BY p.category_id ORDER BY p.price DESC)
ORDER BY p.category_id, p.price DESC, p.id) SELECT ((SELECT array_agg(dense_price_rank ORDER BY row_num) FROM actual WHERE category='ЛР4 тест цены') IS DISTINCT FROM ARRAY[1,1,2]::bigint[])) THEN RAISE EXCEPTION 'DENSE_RANK должен дать 1 1 2'; END IF;
 IF (WITH actual AS (WITH ranked_products AS (
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
ORDER BY r.category_id, r.row_num) SELECT ((SELECT COUNT(*) FROM actual WHERE category='ЛР4 тест цены') <> 3)) THEN RAISE EXCEPTION 'Топ должен дать ровно три товара'; END IF;
 IF (WITH actual AS (WITH ranked_products AS (
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
ORDER BY r.category_id, r.row_num) SELECT (EXISTS (SELECT 1 FROM actual WHERE category='ЛР4 пустая'))) THEN RAISE EXCEPTION 'Пустая категория не должна давать товары'; END IF;
 IF (WITH actual AS (WITH seller_category_sales AS (
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
ORDER BY x.category_id, x.seller_revenue DESC, x.seller_id) SELECT ((SELECT revenue_share FROM actual WHERE store_name='ЛР4 тест 1') IS DISTINCT FROM 0.8::numeric)) THEN RAISE EXCEPTION 'Доля первого продавца 80 процентов'; END IF;
 IF (WITH actual AS (WITH seller_category_sales AS (
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
ORDER BY x.category_id, x.seller_revenue DESC, x.seller_id) SELECT ((SELECT revenue_share FROM actual WHERE store_name='ЛР4 тест 2') IS DISTINCT FROM 0.2::numeric)) THEN RAISE EXCEPTION 'Доля второго продавца 20 процентов'; END IF;
 IF (WITH actual AS (WITH day_sales AS (
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
ORDER BY day) SELECT ((SELECT day_revenue FROM actual WHERE day=DATE '2027-01-02') IS DISTINCT FROM 0::numeric)) THEN RAISE EXCEPTION 'Пропущенный день имеет нулевую выручку'; END IF;
 IF (WITH actual AS (WITH day_sales AS (
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
ORDER BY day) SELECT ((SELECT running_revenue FROM actual WHERE day=DATE '2027-01-03') - (SELECT running_revenue FROM actual WHERE day=DATE '2027-01-01') <> 50)) THEN RAISE EXCEPTION 'Накопление учитывает продажи и пропущенный день'; END IF;
 IF (WITH actual AS (WITH day_sales AS (
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
ORDER BY day) SELECT (NOT EXISTS (SELECT 1 FROM actual WHERE day=DATE '2027-01-03' AND prev_day_revenue=0 AND revenue_growth=50 AND growth_pct IS NULL AND next_day_revenue IS NULL))) THEN RAISE EXCEPTION 'Нулевой предыдущий день и последний LEAD'; END IF;
 IF (WITH actual AS (WITH day_sales AS (
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
ORDER BY day) SELECT (EXISTS (SELECT 1 FROM actual WHERE day=(SELECT MIN(day) FROM actual) AND prev_day_revenue IS NOT NULL))) THEN RAISE EXCEPTION 'Первый LAG должен быть NULL'; END IF;
 IF (WITH actual AS (SELECT p.id, p.category_id, p.title, p.price,
       SUM(p.price) OVER (
           PARTITION BY p.category_id ORDER BY p.price DESC, p.id
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS rows_total,
       SUM(p.price) OVER (
           PARTITION BY p.category_id ORDER BY p.price DESC
           RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS range_total
FROM public.products AS p
ORDER BY p.category_id, p.price DESC, p.id) SELECT ((SELECT array_agg(rows_total ORDER BY price DESC,id) FROM actual WHERE category_id=(SELECT id FROM public.categories WHERE name='ЛР4 тест цены')) IS DISTINCT FROM ARRAY[100,200,250]::numeric[])) THEN RAISE EXCEPTION 'ROWS накапливает по строкам'; END IF;
 IF (WITH actual AS (SELECT p.id, p.category_id, p.title, p.price,
       SUM(p.price) OVER (
           PARTITION BY p.category_id ORDER BY p.price DESC, p.id
           ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS rows_total,
       SUM(p.price) OVER (
           PARTITION BY p.category_id ORDER BY p.price DESC
           RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS range_total
FROM public.products AS p
ORDER BY p.category_id, p.price DESC, p.id) SELECT ((SELECT array_agg(range_total ORDER BY price DESC,id) FROM actual WHERE category_id=(SELECT id FROM public.categories WHERE name='ЛР4 тест цены')) IS DISTINCT FROM ARRAY[200,200,250]::numeric[])) THEN RAISE EXCEPTION 'RANGE включает все равные цены'; END IF;
 RAISE NOTICE 'Граничные случаи лабораторной №4 пройдены';
END $$;
ROLLBACK;
