-- Д1. Запускать целиком в отдельной учебной базе с установленной ЛР5.
-- Сценарий фиксирует собственный заказ, проверяет откат второго и удаляет
-- учебные строки в конце. Служебные последовательности продолжают счёт.
CREATE TEMP TABLE lab05_demo (
    user_id BIGINT NOT NULL,
    seller_id BIGINT NOT NULL,
    category_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    committed_order BIGINT NOT NULL
);

BEGIN;
DO $$
DECLARE
    v_key TEXT := gen_random_uuid()::text;
    v_user BIGINT;
    v_seller BIGINT;
    v_category BIGINT;
    v_product BIGINT;
    v_order BIGINT;
BEGIN
    INSERT INTO public.users (full_name, email)
    VALUES ('ЛР5 Демонстрация', 'lab05+' || v_key || '@example.test')
    RETURNING id INTO v_user;

    INSERT INTO public.sellers (user_id, store_name)
    VALUES (v_user, 'ЛР5 ' || v_key) RETURNING id INTO v_seller;

    INSERT INTO public.categories (name)
    VALUES ('ЛР5 ' || v_key) RETURNING id INTO v_category;

    INSERT INTO public.products (seller_id, category_id, title, price)
    VALUES (v_seller, v_category, 'ЛР5 Тестовый товар', 100)
    RETURNING id INTO v_product;

    INSERT INTO public.stock (product_id, quantity) VALUES (v_product, 5);
    v_order := public.place_order(v_user, v_product, 2);
    INSERT INTO lab05_demo VALUES (v_user, v_seller, v_category, v_product, v_order);
END;
$$;
COMMIT;

SELECT 'После COMMIT' AS step, s.quantity AS stock_left,
       (SELECT COUNT(*) FROM public.orders WHERE user_id = d.user_id) AS orders,
       (SELECT COUNT(*) FROM public.order_items
        WHERE product_id = d.product_id) AS items
FROM lab05_demo AS d
JOIN public.stock AS s ON s.product_id = d.product_id;

BEGIN;
DO $$
DECLARE
    d lab05_demo%ROWTYPE;
BEGIN
    SELECT * INTO STRICT d FROM lab05_demo;

    -- Валидный заказ в этой транзакции успевает изменить данные.
    PERFORM public.place_order(d.user_id, d.product_id, 1);

    -- Ошибка намеренная. Вложенный блок позволяет DBeaver продолжить
    -- сценарий до явного ROLLBACK внешней транзакции.
    BEGIN
        PERFORM public.place_order(d.user_id, d.product_id, 99);
        RAISE EXCEPTION 'Ожидалась ошибка нехватки остатка';
    EXCEPTION WHEN SQLSTATE 'P5001' THEN
        RAISE NOTICE 'Ожидаемая ошибка P5001: %', SQLERRM;
    END;
END;
$$;

SELECT 'Перед ROLLBACK' AS step, s.quantity AS stock_left,
       (SELECT COUNT(*) FROM public.orders WHERE user_id = d.user_id) AS orders,
       (SELECT COUNT(*) FROM public.order_items
        WHERE product_id = d.product_id) AS items
FROM lab05_demo AS d
JOIN public.stock AS s ON s.product_id = d.product_id;
ROLLBACK;

SELECT 'После ROLLBACK' AS step, s.quantity AS stock_left,
       (SELECT COUNT(*) FROM public.orders WHERE user_id = d.user_id) AS orders,
       (SELECT COUNT(*) FROM public.order_items
        WHERE product_id = d.product_id) AS items
FROM lab05_demo AS d
JOIN public.stock AS s ON s.product_id = d.product_id;

-- Проверка результата и очистка демонстрационных строк.
BEGIN;
DO $$
DECLARE
    d lab05_demo%ROWTYPE;
BEGIN
    SELECT * INTO STRICT d FROM lab05_demo;
    IF (SELECT quantity FROM public.stock WHERE product_id = d.product_id)
            IS DISTINCT FROM 3
       OR (SELECT COUNT(*) FROM public.orders WHERE user_id = d.user_id) <> 1
       OR (SELECT COUNT(*) FROM public.order_items WHERE product_id = d.product_id) <> 1
       OR NOT EXISTS (
           SELECT 1 FROM public.order_items
           WHERE order_id = d.committed_order AND product_id = d.product_id
             AND quantity = 2 AND unit_price = 100
       ) THEN
        RAISE EXCEPTION 'Некорректный результат демонстрации транзакций';
    END IF;

    DELETE FROM public.orders WHERE id = d.committed_order;
    DELETE FROM public.products WHERE id = d.product_id;
    DELETE FROM public.categories WHERE id = d.category_id;
    DELETE FROM public.sellers WHERE id = d.seller_id;
    DELETE FROM public.users WHERE id = d.user_id;
    RAISE NOTICE 'Демонстрация COMMIT и ROLLBACK пройдена';
END;
$$;
DROP TABLE lab05_demo;
COMMIT;
