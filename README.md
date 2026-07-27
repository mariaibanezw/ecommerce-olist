# Análisis de E-commerce con SQL — Dataset Olist

Proyecto de análisis exploratorio sobre el dataset público de [Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (marketplace brasileño), resuelto íntegramente con consultas SQL sobre una base SQLite armada a partir de los 9 CSV originales.

El objetivo es mostrar manejo de SQL en distintos niveles: `SELECT`/`WHERE`/`GROUP BY` básicos, joins múltiples, subqueries, CTEs y funciones de ventana (window functions).

## Estructura de la base

| Tabla | Filas 
|---|---|
| `orders` | Pedidos — tabla central del modelo |
| `order_items` | Items vendidos por pedido |
| `order_payments` | Pagos realizados por pedido |
| `order_reviews` | Reviews de clientes |
| `customers` | Clientes |
| `products` | Catálogo de productos |
| `sellers` | Vendedores |
| `geolocation` | Coordenadas por código postal |
| `category_translation` | Traducción de categorías (PT → EN) |

El archivo `olist.db` incluido en este repo ya tiene los 9 CSV cargados..

## Preguntas y consultas

### 1. ¿Cuántos pedidos hay en total, y cómo se distribuyen por estado?

```sql
SELECT count(*) AS total_pedidos
FROM orders;

SELECT order_status AS estado, count(*) AS total_pedidos
FROM orders
GROUP BY order_status
ORDER BY total_pedidos DESC;
```

**Resultado:** 99.441 pedidos en total. 96.478 pedidos están en estado `delivered`; el resto se reparte entre `shipped`, `canceled`, `unavailable`, `invoiced`, `processing`, `created` y `approved`.

### 2. Top 10 productos por precio más alto

```sql
SELECT product_id AS producto, price AS precio
FROM order_items
ORDER BY price DESC
LIMIT 10;
```

**Resultado:** el producto más caro vendido tuvo un precio de R$ 6.735, seguido de cerca por otros dos productos por encima de R$ 6.700.

### 3. Top 10 pedidos por monto pagado

```sql
SELECT o.order_id AS pedidos, op.payment_value AS valor_pago
FROM orders o
LEFT JOIN order_payments op ON op.order_id = o.order_id
ORDER BY payment_value DESC
LIMIT 10;
```

**Resultado:** el pedido de mayor monto pagado es de R$ 13.664, muy por encima del segundo (R$ 7.275).

### 4. Top 10 categorías con mayor facturación

```sql
SELECT ct.product_category_name_english AS categoria,
       SUM(oi.price) AS total_facturacion,
       COUNT(DISTINCT oi.order_id) AS total_ventas
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
JOIN category_translation ct ON p.product_category_name = ct.product_category_name
GROUP BY ct.product_category_name_english
ORDER BY total_facturacion DESC
LIMIT 10;
```

**Resultado:** `health_beauty` es la categoria con mayor facturacion: R$ 1.258.681, seguida de `watches_gifts` (R$ 1.205.005) y `bed_bath_table` (R$ 1.036.988).

### 5. Top 10 productos más vendidos por cantidad de unidades

```sql
SELECT oi.product_id AS producto, COUNT(o.order_id) AS cantidad
FROM orders o
JOIN order_items oi ON o.order_id = oi.order_id
GROUP BY producto
ORDER BY cantidad DESC
LIMIT 10;
```

**Resultado:** el producto más vendido, se vendió 527 veces — un ranking distinto al de facturación, diferenciando "lo que más vende" de "lo que más factura".

### 6. Top 5 ciudades con más pedidos y su ticket promedio

```sql
SELECT c.customer_city AS ciudad,
       COUNT(o.order_id) AS pedidos,
       ROUND(AVG(op.payment_value), 2) AS ticket_promedio
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
LEFT JOIN order_payments op ON op.order_id = o.order_id
GROUP BY customer_city
ORDER BY pedidos DESC
LIMIT 5;
```

**Resultado:** São Paulo concentra la mayor cantidad de pedidos (16.221), pero no tiene el ticket promedio más alto. 

### 7. % de pedidos con comentario de review

```sql
WITH con_comentario AS (
    SELECT COUNT(DISTINCT order_id) AS pedidos_con_comentario
    FROM order_reviews
    WHERE review_comment_message IS NOT NULL
      AND review_comment_message <> ''
),
total AS (
    SELECT COUNT(*) AS total_pedidos FROM orders
)
SELECT t.total_pedidos, cc.pedidos_con_comentario,
       ROUND(cc.pedidos_con_comentario * 100.0 / t.total_pedidos, 2) AS porcentaje
FROM total t
CROSS JOIN con_comentario cc;
```

**Resultado:** solo el 41,07% de los pedidos tiene un comentario de texto en su review (40.836 de 99.441) — la mayoría de los clientes deja una puntuación pero no explica el motivo.

### 8. Facturación mensual y % de crecimiento mes a mes

```sql
WITH facturacion_mensual AS (
    SELECT strftime('%Y-%m', o.order_purchase_timestamp) AS año_mes,
           SUM(i.price) AS facturacion
    FROM order_items i
    LEFT JOIN orders o ON i.order_id = o.order_id
    GROUP BY año_mes
)
SELECT año_mes, facturacion,
       LAG(facturacion) OVER (ORDER BY año_mes) AS mes_anterior,
       ROUND(
           (facturacion - LAG(facturacion) OVER (ORDER BY año_mes))
           / LAG(facturacion) OVER (ORDER BY año_mes) * 100, 2
       ) AS porcentaje
FROM facturacion_mensual
ORDER BY año_mes;
```

**Resultado:** la facturación crece de forma sostenida desde fines de 2016 hasta un pico en noviembre 2017, y se estabiliza en torno a los R$ 850.000–1.000.000 mensuales durante 2018. 

### 9. % de pedidos que llegan tarde, por estado del cliente

```sql
WITH total_pedidos AS (
    SELECT c.customer_state, COUNT(o.order_id) AS total
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_state
),
total_demorados AS (
    SELECT c.customer_state, COUNT(o.order_id) AS demorados
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date > o.order_estimated_delivery_date
    GROUP BY c.customer_state
)
SELECT tp.customer_state, tp.total, td.demorados,
       ROUND(td.demorados * 100.0 / tp.total, 2) AS porcentaje
FROM total_pedidos tp
JOIN total_demorados td ON tp.customer_state = td.customer_state
ORDER BY porcentaje DESC;
```

**Resultado:** Alagoas (AL) tiene la peor performance logística, con 23,93% de pedidos tarde, seguido de Maranhão y Piauí.

### 10. Primera y última compra por cliente, y días entre ambas

```sql
SELECT DISTINCT c.customer_unique_id AS cliente,
       MIN(o.order_purchase_timestamp) AS primera_compra,
       MAX(o.order_purchase_timestamp) AS ultima_compra,
       ROUND(julianday(MAX(o.order_purchase_timestamp))
             - julianday(MIN(o.order_purchase_timestamp)), 0) AS dias
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_unique_id
HAVING dias > 0
ORDER BY dias DESC;
```

**Resultado:** la gran mayoría de los clientes de Olist compró una sola vez. El cliente más recurrente del dataset tuvo 633 días entre su primera y su última compra — la recurrencia real es baja, típico de un marketplace con alta proporción de compradores ocasionales.

### 11. Ticket promedio y % del total por método de pago

```sql
WITH total_pagos AS (
    SELECT SUM(payment_value) AS total FROM order_payments
)
SELECT op.payment_type AS forma_pago,
       ROUND(AVG(op.payment_value), 2) AS ticket_prom,
       COUNT(*) AS cantidad_pagos,
       ROUND(SUM(op.payment_value) * 100.0 / t.total, 2) AS porcentaje
FROM order_payments op
CROSS JOIN total_pagos t
GROUP BY op.payment_type, t.total
ORDER BY porcentaje DESC;
```

**Resultado:** la tarjeta de crédito domina el mix de pagos (78,34% del total), seguida por boleto (17,92%). El voucher tiene el ticket promedio más bajo (R$ 65,70), consistente con su uso típico como cupón parcial más que como medio de pago principal.

## Herramientas utilizadas

- **SQLite** como motor de base de datos
- Consultas con `JOIN`, `GROUP BY`, `HAVING`, `CASE WHEN`, subqueries, `CTE` (`WITH`) y funciones de ventana (`LAG() OVER`)

## Cómo explorar la base

El archivo `olist.db` se puede abrir sin instalar nada con herramientas online como [sqliteviewer.app](https://sqliteviewer.app) o [sqliteonline.com](https://sqliteonline.com), o localmente con [DB Browser for SQLite](https://sqlitebrowser.org/).
