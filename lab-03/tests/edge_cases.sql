-- Запускать в тестовой БД после all.sql. Все фикстуры откатываются.
BEGIN;
DO $$
DECLARE
    u bigint; empty_u bigint; buyer bigint; seller bigint; empty_seller bigint;
    root bigint; child bigint; leaf bigint; p1 bigint; p2 bigint;
    paid_order bigint; pending_order bigint; actual record; d integer;
BEGIN
    INSERT INTO public.users(full_name,email) VALUES ('LR3 test seller','lr3-test-seller@example.test') RETURNING id INTO u;
    INSERT INTO public.users(full_name,email) VALUES ('LR3 empty seller','lr3-test-empty@example.test') RETURNING id INTO empty_u;
    INSERT INTO public.users(full_name,email) VALUES ('LR3 buyer','lr3-test-buyer@example.test') RETURNING id INTO buyer;
    INSERT INTO public.sellers(user_id,store_name) VALUES (u,'LR3 test shop') RETURNING id INTO seller;
    INSERT INTO public.sellers(user_id,store_name) VALUES (empty_u,'LR3 empty shop') RETURNING id INTO empty_seller;
    INSERT INTO public.categories(name) VALUES ('LR3 test root') RETURNING id INTO root;
    INSERT INTO public.categories(parent_id,name) VALUES (root,'LR3 test child') RETURNING id INTO child;
    INSERT INTO public.categories(parent_id,name) VALUES (child,'LR3 test leaf') RETURNING id INTO leaf;
    INSERT INTO public.products(seller_id,category_id,title,price) VALUES (seller,leaf,'LR3 first',100) RETURNING id INTO p1;
    INSERT INTO public.products(seller_id,category_id,title,price) VALUES (seller,leaf,'LR3 second',300) RETURNING id INTO p2;
    INSERT INTO public.orders(user_id,status) VALUES (buyer,'paid') RETURNING id INTO paid_order;
    INSERT INTO public.orders(user_id) VALUES (buyer) RETURNING id INTO pending_order;
    INSERT INTO public.order_items VALUES (paid_order,p1,2,125), (pending_order,p2,3,300);
    INSERT INTO public.payments(order_id,amount,status) VALUES (paid_order,250,'completed'), (pending_order,900,'pending');
    INSERT INTO public.reviews(user_id,product_id,score) VALUES (buyer,p1,4), (buyer,p1,5);

    SELECT * INTO actual FROM public.lr3_seller_report WHERE seller_id = seller;
    IF actual.products_count <> 2 OR actual.paid_orders_count <> 1
       OR actual.units_sold <> 2 OR actual.paid_sales_amount <> 250 THEN
        RAISE EXCEPTION 'Ошибка отчёта: размножение строк, неоплаченный заказ или текущая цена вместо исторической';
    END IF;
    SELECT * INTO actual FROM public.lr3_seller_report WHERE seller_id = empty_seller;
    IF actual.products_count <> 0 OR actual.paid_sales_amount <> 0 THEN
        RAISE EXCEPTION 'Продавец без товаров должен иметь нули';
    END IF;
    SELECT COUNT(p.id) AS n, AVG(p.price) AS avg INTO actual
    FROM public.categories AS c LEFT JOIN public.products AS p ON p.category_id = c.id
    WHERE c.id = root GROUP BY c.id;
    IF actual.n <> 0 OR actual.avg IS NOT NULL THEN
        RAISE EXCEPTION 'Пустая категория: ожидаются 0 и NULL';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.products AS p LEFT JOIN public.reviews AS r ON r.product_id = p.id WHERE p.id = p2 AND r.id IS NULL)
       OR EXISTS (SELECT 1 FROM public.products AS p LEFT JOIN public.reviews AS r ON r.product_id = p.id WHERE p.id = p1 AND r.id IS NULL) THEN
        RAISE EXCEPTION 'Неверный поиск товаров без отзывов';
    END IF;
    WITH RECURSIVE tree AS (
        SELECT id, 0 AS depth, ARRAY[id] AS path_ids FROM public.categories WHERE id = root
        UNION ALL
        SELECT c.id, t.depth+1, t.path_ids || c.id
        FROM public.categories AS c JOIN tree AS t ON c.parent_id=t.id
        WHERE NOT (c.id = ANY(t.path_ids))
    ) SELECT depth INTO d FROM tree WHERE id=leaf;
    IF d IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'Не достигнут внук категории'; END IF;
    RAISE NOTICE 'Граничные случаи ЛР3 пройдены';
END $$;
ROLLBACK;
