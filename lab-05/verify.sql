-- Д2–Д5. Проверки функций и триггеров на собственных учебных строках.
BEGIN;

DO $$
DECLARE
    v_key TEXT := gen_random_uuid()::text;
    v_user BIGINT;
    v_seller BIGINT;
    v_category BIGINT;
    v_product BIGINT;
    v_other_product BIGINT;
    v_paid_order BIGINT;
    v_pending_order BIGINT;
    v_review BIGINT;
    v_other_review BIGINT;
    v_period_start TIMESTAMPTZ;
BEGIN
    INSERT INTO public.users (full_name, email)
    VALUES ('ЛР5 Проверка', 'lab05+' || v_key || '@example.test')
    RETURNING id INTO v_user;
    INSERT INTO public.sellers (user_id, store_name)
    VALUES (v_user, 'ЛР5 ' || v_key) RETURNING id INTO v_seller;
    INSERT INTO public.categories (name)
    VALUES ('ЛР5 ' || v_key) RETURNING id INTO v_category;
    INSERT INTO public.products (seller_id, category_id, title, price)
    VALUES (v_seller, v_category, 'ЛР5 Первый товар', 125)
    RETURNING id INTO v_product;
    INSERT INTO public.products (seller_id, category_id, title, price)
    VALUES (v_seller, v_category, 'ЛР5 Второй товар', 250)
    RETURNING id INTO v_other_product;
    INSERT INTO public.stock (product_id, quantity) VALUES (v_product, 5);

    -- Д2. Заказ, позиция и склад согласованы.
    v_paid_order := public.place_order(v_user, v_product, 2);
    IF NOT EXISTS (
        SELECT 1 FROM public.orders AS o
        JOIN public.order_items AS i ON i.order_id = o.id
        JOIN public.stock AS s ON s.product_id = i.product_id
        WHERE o.id = v_paid_order AND o.user_id = v_user AND o.status = 'pending'
          AND i.product_id = v_product AND i.quantity = 2
          AND i.unit_price = 125 AND s.quantity = 3
    ) THEN
        RAISE EXCEPTION 'Д2: неверное оформление заказа';
    END IF;

    BEGIN
        PERFORM public.place_order(v_user, v_product, 4);
        RAISE EXCEPTION 'Д2: ожидалась нехватка товара';
    EXCEPTION WHEN SQLSTATE 'P5001' THEN
        RAISE NOTICE 'Д2: нехватка остатка отклонена (P5001)';
    END;
    BEGIN
        PERFORM public.place_order(v_user, v_other_product, 1);
        RAISE EXCEPTION 'Д2: ожидалось отсутствие записи склада';
    EXCEPTION WHEN SQLSTATE 'P5001' THEN NULL;
    END;
    BEGIN
        PERFORM public.place_order(v_user, v_product, 0);
        RAISE EXCEPTION 'Д2: ожидалось отклонение нулевого количества';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    -- Сбой после UPDATE stock: внешний ключ отклоняет покупателя.
    BEGIN
        PERFORM public.place_order(-1, v_product, 1);
        RAISE EXCEPTION 'Д2: ожидалась ошибка внешнего ключа';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    IF (SELECT quantity FROM public.stock WHERE product_id = v_product)
            IS DISTINCT FROM 3
       OR (SELECT COUNT(*) FROM public.orders WHERE user_id = v_user) <> 1
       OR (SELECT COUNT(*) FROM public.order_items
           WHERE product_id = v_product) <> 1 THEN
        RAISE EXCEPTION 'Д2: после ошибки осталось частичное изменение';
    END IF;
    RAISE NOTICE 'Д2: после ошибки внешнего ключа остаток снова 3';

    -- Д3. Историческая цена, статус платежа и обе границы периода.
    v_pending_order := public.place_order(v_user, v_product, 1);
    INSERT INTO public.payments (order_id, amount, status)
    VALUES (v_paid_order, 250, 'completed'), (v_pending_order, 125, 'pending');
    SELECT created_at INTO STRICT v_period_start
    FROM public.orders WHERE id = v_paid_order;

    -- Д4. Реальное изменение цены и запись с тем же значением.
    UPDATE public.products SET price = 150 WHERE id = v_product;
    UPDATE public.products SET price = 150 WHERE id = v_product;
    IF public.seller_revenue(v_seller, v_period_start, v_period_start + INTERVAL '1 day')
            IS DISTINCT FROM 250
       OR public.seller_revenue(v_seller, v_period_start - INTERVAL '1 day', v_period_start)
            IS DISTINCT FROM 0 THEN
        RAISE EXCEPTION 'Д3: неверная выручка или граница периода';
    END IF;
    RAISE NOTICE 'Д3: оплаченная выручка 250, за исключающей верхней границей 0';

    BEGIN
        PERFORM public.seller_revenue(v_seller, v_period_start, v_period_start);
        RAISE EXCEPTION 'Д3: ожидалось отклонение пустого периода';
    EXCEPTION WHEN invalid_parameter_value THEN NULL;
    END;

    IF (SELECT COUNT(*) FROM public.product_price_audit WHERE product_id = v_product) <> 1
       OR NOT EXISTS (
           SELECT 1 FROM public.product_price_audit WHERE product_id = v_product
             AND old_price = 125 AND new_price = 150 AND changed_by = current_user
       ) THEN
        RAISE EXCEPTION 'Д4: неверная запись аудита';
    END IF;
    RAISE NOTICE 'Д4: одна запись аудита 125 → 150';

    -- Д5. Вставка, смена оценки, перенос и удаление отзыва.
    INSERT INTO public.reviews (user_id, product_id, score)
    VALUES (v_user, v_product, 5) RETURNING id INTO v_review;
    INSERT INTO public.reviews (user_id, product_id, score)
    VALUES (v_user, v_product, 3) RETURNING id INTO v_other_review;
    IF (SELECT rating FROM public.products WHERE id = v_product) IS DISTINCT FROM 4.00 THEN
        RAISE EXCEPTION 'Д5: рейтинг после вставки должен быть 4,00';
    END IF;

    UPDATE public.reviews SET score = 1 WHERE id = v_other_review;
    IF (SELECT rating FROM public.products WHERE id = v_product) IS DISTINCT FROM 3.00 THEN
        RAISE EXCEPTION 'Д5: рейтинг после изменения должен быть 3,00';
    END IF;

    UPDATE public.reviews SET product_id = v_other_product WHERE id = v_other_review;
    DELETE FROM public.reviews WHERE id = v_review;
    IF (SELECT rating FROM public.products WHERE id = v_product) IS NOT NULL
       OR (SELECT rating FROM public.products WHERE id = v_other_product)
            IS DISTINCT FROM 1.00 THEN
        RAISE EXCEPTION 'Д5: неверные рейтинги после переноса и удаления';
    END IF;

    RAISE NOTICE 'Д5: 4,00 → 3,00 → NULL у первого товара и 1,00 у второго';
    RAISE NOTICE 'Проверки лабораторной №5 пройдены';
END;
$$;

ROLLBACK;
