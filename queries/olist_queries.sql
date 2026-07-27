-- ¿Cuántos pedidos hay en total en la tabla orders?
-- ¿Cuántos pedidos hay por cada order_status?
select 
	count(*) AS total_pedidos
FROM orders;

select 
	order_status AS estado,
	count(*) AS total_pedidos
FROM orders
GROUP BY order_status;


--¿Cuáles son los 10 productos con el precio más alto? 
select 
product_id AS producto,
price as precio
FROM order_items
order by price DESC
LIMIT 10;


-- ¿Cuáles son los 10 pedidos con el payment_value más alto?
SELECT 
o.order_id AS pedidos,
op.payment_value AS valor_pago
FROM orders o
left join order_payments op on op.order_id = o.order_id
order by payment_value DESC
LIMIT 10


-- ¿Cuáles son las 10 categorías de producto con mayor facturación total?
select
   ct.product_category_name_english AS categoria,
   SUM(oi.price) AS total_facturacion,
   COUNT(DISTINCT oi.order_id) AS total_ventas
FROM order_items oi
JOIN products p 
    ON oi.product_id = p.product_id
JOIN category_translation ct 
    ON p.product_category_name = ct.product_category_name
GROUP BY ct.product_category_name_english
ORDER BY total_facturacion DESC
LIMIT 10;


-- ¿Cuáles son los 10 productos que más veces se vendieron (por cantidad de veces que aparecen en order_items), no por facturación?
select 
oi.product_id as producto,
count(o.order_id) as cantidad
FROM orders o
join order_items oi ON o.order_id = oi.order_id
group by producto
order by cantidad desc
limit 10;


-- ¿Cuáles son las 5 ciudades de clientes (customer_city) con más pedidos, y cuál es el ticket promedio en cada una?
select 
c.customer_city AS ciudad,
count(o.order_id) as pedidos,
ROUND(AVG(op.payment_value), 2) as ticket_promedio
FROM orders o 
LEFT JOIN customers c on o.customer_id = c.customer_id
LEFT JOIN order_payments op ON op.order_id = o.order_id
GROUP BY customer_city
order by pedidos DESC
LIMIT 5
;


-- ¿Qué porcentaje de pedidos tiene una review con review_comment_message no vacío?
WITH con_comentario AS (
    SELECT COUNT(DISTINCT order_id) AS pedidos_con_comentario
    FROM order_reviews
    WHERE review_comment_message IS NOT NULL
      AND review_comment_message <> ''
),
total AS (
    SELECT COUNT(*) AS total_pedidos
    FROM orders
)
SELECT 
    t.total_pedidos,
    cc.pedidos_con_comentario,
    ROUND(cc.pedidos_con_comentario * 100.0 / t.total_pedidos, 2) AS porcentaje
FROM total t
CROSS JOIN con_comentario cc;



-- ¿Cuál es la facturacion mensual y el % de crecimiento mes a mes?
WITH facturacion_mensual AS (
    SELECT 
        strftime('%Y-%m', o.order_purchase_timestamp) AS año_mes,
        SUM(i.price) AS facturacion
    FROM order_items i
     LEFT JOIN orders o 
        ON i.order_id = o.order_id
    GROUP BY año_mes
)
SELECT 
    año_mes,
    facturacion,
    LAG(facturacion) OVER (ORDER BY año_mes) AS mes_anterior,
    ROUND(
        (facturacion - LAG(facturacion) OVER (ORDER BY año_mes)) 
        / LAG(facturacion) OVER (ORDER BY año_mes) * 100, 2
    ) AS porcentaje -- redondear porque dan muchos decimales
FROM facturacion_mensual
ORDER BY año_mes;


-- ¿Qué % de pedidos llega tarde respecto a la fecha estimada de entrega, por estado (state) del cliente?
WITH total_pedidos AS (
    SELECT 
        c.customer_state,
        COUNT(o.order_id) AS total
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_state
),
total_demorados AS (
    SELECT 
        c.customer_state,
        COUNT(o.order_id) AS demorados
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date > o.order_estimated_delivery_date
    GROUP BY c.customer_state
)
SELECT 
    tp.customer_state,
    tp.total,
    td.demorados,
    ROUND(td.demorados * 100.0 / tp.total, 2) AS porcentaje
FROM total_pedidos tp
JOIN total_demorados td 
    ON tp.customer_state = td.customer_state
ORDER BY porcentaje DESC;


-- Para cada cliente, ¿cuál fue su primer y su último pedido, y cuántos días pasaron entre ambos? 
SELECT DISTINCT
c.customer_unique_id AS cliente,
MIN(o.order_purchase_timestamp) as primera_compra,
Max(o.order_purchase_timestamp) AS ultima_compra,
ROUND(julianday(MAX(o.order_purchase_timestamp)) - julianday(MIN(o.order_purchase_timestamp)),0) AS dias 
from customers c
left JOIN orders o on c.customer_id = o.customer_id
GROUP BY c.customer_unique_id
HAVING dias > 0
ORDER BY dias DESC;



-- ¿Cuál es el ticket promedio por método de pago, y qué % del total de pagos representa cada método? 
WITH
total_pagos AS (
  SELECT SUM(payment_value) AS total FROM order_payments
)  
SELECT 
    op.payment_type AS forma_pago,
    ROUND(AVG(op.payment_value), 2) AS ticket_prom,
    COUNT(*) AS cantidad_pagos,
    ROUND(SUM(op.payment_value) * 100.0 / t.total, 2) AS porcentaje
FROM order_payments op
CROSS JOIN total_pagos t
GROUP BY op.payment_type, t.total
ORDER BY porcentaje DESC;





