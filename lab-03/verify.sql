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
