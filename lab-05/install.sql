-- ЛР5. Расширения существующей схемы маркетплейса.
-- Выполнять целиком после ЛР1.
BEGIN;

-- Отзывы не меняются, пока создаются триггер и исходные итоги.
LOCK TABLE public.reviews IN SHARE ROW EXCLUSIVE MODE;

-- Журнал сохраняет историю даже после удаления товара.
CREATE TABLE IF NOT EXISTS public.product_price_audit (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL,
    old_price NUMERIC(12, 2) NOT NULL,
    new_price NUMERIC(12, 2) NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    changed_by NAME NOT NULL DEFAULT current_user
);

ALTER TABLE public.products
    ADD COLUMN IF NOT EXISTS rating_sum BIGINT NOT NULL DEFAULT 0
        CHECK (rating_sum >= 0),
    ADD COLUMN IF NOT EXISTS rating_count BIGINT NOT NULL DEFAULT 0
        CHECK (rating_count >= 0),
    ADD COLUMN IF NOT EXISTS rating NUMERIC(3, 2) GENERATED ALWAYS AS (
        round(rating_sum::numeric / NULLIF(rating_count, 0), 2)
    ) STORED;

-- В этой версии заказа одна позиция с произвольным количеством.
CREATE OR REPLACE FUNCTION public.place_order(
    p_user BIGINT, p_product BIGINT, p_qty INTEGER
)
RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
    v_order_id BIGINT;
    v_price NUMERIC(12, 2);
BEGIN
    IF p_user IS NULL OR p_product IS NULL OR p_qty IS NULL OR p_qty <= 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Требуются покупатель, товар и положительное количество';
    END IF;

    SELECT price INTO v_price
    FROM public.products
    WHERE id = p_product AND is_active;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Активный товар % не найден', p_product
            USING ERRCODE = 'P5002';
    END IF;

    -- Проверка и списание под блокировкой одной строки склада.
    UPDATE public.stock
    SET quantity = quantity - p_qty, updated_at = clock_timestamp()
    WHERE product_id = p_product AND quantity >= p_qty;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Недостаточный остаток товара %', p_product
            USING ERRCODE = 'P5001';
    END IF;

    INSERT INTO public.orders (user_id)
    VALUES (p_user)
    RETURNING id INTO v_order_id;

    INSERT INTO public.order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, p_product, p_qty, v_price);

    RETURN v_order_id;
END;
$$;

-- Период по времени создания заказа: нижняя граница включена, верхняя исключена.
CREATE OR REPLACE FUNCTION public.seller_revenue(
    p_seller BIGINT, p_from TIMESTAMPTZ, p_to TIMESTAMPTZ
)
RETURNS NUMERIC
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_revenue NUMERIC;
BEGIN
    IF p_seller IS NULL OR p_from IS NULL OR p_to IS NULL OR p_from >= p_to THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Укажите продавца и корректные границы периода';
    END IF;

    SELECT COALESCE(SUM(oi.quantity * oi.unit_price), 0) INTO v_revenue
    FROM public.orders AS o
    JOIN public.order_items AS oi ON oi.order_id = o.id
    JOIN public.products AS p ON p.id = oi.product_id
    JOIN public.payments AS pay ON pay.order_id = o.id
    WHERE p.seller_id = p_seller
      AND pay.status = 'completed'
      AND o.created_at >= p_from AND o.created_at < p_to;

    RETURN v_revenue;
END;
$$;

CREATE OR REPLACE FUNCTION public.audit_product_price()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.product_price_audit (product_id, old_price, new_price)
    VALUES (NEW.id, OLD.price, NEW.price);
    RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER trg_lab05_audit_price
AFTER UPDATE OF price ON public.products
FOR EACH ROW
WHEN (OLD.price IS DISTINCT FROM NEW.price)
EXECUTE FUNCTION public.audit_product_price();

CREATE OR REPLACE FUNCTION public.update_product_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_old_id BIGINT;
    v_new_id BIGINT;
    v_old_score INTEGER;
    v_new_score INTEGER;
    v_delta RECORD;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        v_old_id := OLD.product_id;
        v_old_score := OLD.score;
    END IF;
    IF TG_OP <> 'DELETE' THEN
        v_new_id := NEW.product_id;
        v_new_score := NEW.score;
    END IF;

    -- Изменение оценки в пределах товара сводится к одной разнице.
    -- При переносе отзыва оба товара обновляются в порядке id.
    FOR v_delta IN
        SELECT product_id, SUM(score_delta) AS score, SUM(count_delta) AS reviews
        FROM (VALUES (v_old_id, -v_old_score, -1),
                     (v_new_id,  v_new_score,  1)
        ) AS changes(product_id, score_delta, count_delta)
        WHERE product_id IS NOT NULL
        GROUP BY product_id
        HAVING SUM(score_delta) <> 0 OR SUM(count_delta) <> 0
        ORDER BY product_id
    LOOP
        UPDATE public.products
        SET rating_sum = rating_sum + v_delta.score,
            rating_count = rating_count + v_delta.reviews
        WHERE id = v_delta.product_id;
    END LOOP;

    RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER trg_lab05_update_rating
AFTER INSERT OR UPDATE OF score, product_id OR DELETE ON public.reviews
FOR EACH ROW EXECUTE FUNCTION public.update_product_rating();

-- Учитываем и отзывы, которые были добавлены до установки ЛР5.
WITH totals AS (
    SELECT product_id, SUM(score) AS rating_sum, COUNT(*) AS rating_count
    FROM public.reviews
    GROUP BY product_id
), expected AS (
    SELECT p.id, COALESCE(t.rating_sum, 0) AS rating_sum,
           COALESCE(t.rating_count, 0) AS rating_count
    FROM public.products AS p
    LEFT JOIN totals AS t ON t.product_id = p.id
)
UPDATE public.products AS p
SET rating_sum = e.rating_sum, rating_count = e.rating_count
FROM expected AS e
WHERE p.id = e.id
  AND (p.rating_sum, p.rating_count) IS DISTINCT FROM (e.rating_sum, e.rating_count);

COMMIT;
