-- Проверки результата наполнения. Данные не изменяются.
-- Ранее добавленные строки могут увеличивать общие количества.
DO $$
DECLARE
    buyer_id bigint;
    table_name text;
    actual_count bigint;
BEGIN
    FOREACH table_name IN ARRAY ARRAY['users', 'sellers', 'categories', 'products',
        'stock', 'carts', 'cart_items', 'addresses', 'orders', 'order_items',
        'payments', 'deliveries', 'reviews'] LOOP
        EXECUTE format('SELECT count(*) FROM public.%I', table_name) INTO actual_count;
        IF actual_count = 0 THEN RAISE EXCEPTION 'Таблица % пуста', table_name; END IF;
    END LOOP;
    SELECT id INTO STRICT buyer_id FROM public.users WHERE email = 'buyer@lr2.example.test';
    IF (SELECT COUNT(*) FROM public.products WHERE title LIKE 'ЛР2 %') <> 1200
       OR (SELECT COUNT(*) FROM public.orders
           WHERE user_id = buyer_id AND created_at >= TIMESTAMPTZ '2026-09-01 09:00:00+03'
           AND created_at < TIMESTAMPTZ '2026-09-26 09:00:00+03') <> 1200 THEN
        RAISE EXCEPTION 'Ожидалась партия из 1200 товаров и 1200 заказов';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.orders AS o
        WHERE o.user_id = buyer_id
          AND (SELECT COUNT(*) FROM public.order_items AS i WHERE i.order_id = o.id) <> 2
    ) THEN RAISE EXCEPTION 'Учебный заказ должен содержать две позиции'; END IF;
    IF EXISTS (
        SELECT 1 FROM public.products AS p WHERE NOT EXISTS (
            SELECT 1 FROM public.stock AS s WHERE s.product_id = p.id
        )
    ) THEN RAISE EXCEPTION 'Есть товар без остатка'; END IF;
    IF EXISTS (
        SELECT 1 FROM public.payments AS p JOIN public.orders AS o ON o.id = p.order_id
        WHERE o.user_id = buyer_id
          AND p.amount <> (SELECT SUM(i.quantity * i.unit_price)
                           FROM public.order_items AS i WHERE i.order_id = p.order_id)
    ) OR EXISTS (
        SELECT 1 FROM public.deliveries AS d
        JOIN public.orders AS o ON o.id = d.order_id
        JOIN public.addresses AS a ON a.id = d.address_id
        WHERE o.user_id = buyer_id AND a.user_id <> o.user_id
    ) THEN RAISE EXCEPTION 'Нарушена согласованность платежей или доставок'; END IF;
    IF (SELECT COUNT(*) FROM public.products WHERE title LIKE 'ЛР2 %' AND description IS NULL) <> 172
       OR (SELECT COUNT(*) FROM public.products WHERE title LIKE 'ЛР2 %' AND NOT is_active) <> 300
       OR (SELECT COUNT(*) FROM public.products
           WHERE title LIKE 'ЛР2 %' AND price BETWEEN 1000 AND 2000) <> 36 THEN
        RAISE EXCEPTION 'Неверное распределение тестовых значений';
    END IF;
    IF EXISTS (
        (SELECT id FROM public.products WHERE title LIKE 'ЛР2 %'
         ORDER BY price DESC, id ASC LIMIT 10)
        INTERSECT
        (SELECT id FROM public.products WHERE title LIKE 'ЛР2 %'
         ORDER BY price DESC, id ASC LIMIT 10 OFFSET 10)
    ) THEN RAISE EXCEPTION 'Страницы пересекаются'; END IF;
    RAISE NOTICE 'Проверки лабораторной №2 пройдены';
END $$;
