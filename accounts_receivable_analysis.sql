USE accounts_receivable_db;


-- views used by the queries below

CREATE OR REPLACE VIEW vw_payment_totals AS
SELECT
    invoice_id,
    SUM(payment_amount) AS total_paid,
    MIN(payment_date) AS first_payment_date,
    MAX(payment_date) AS last_payment_date
FROM payments
GROUP BY invoice_id;

CREATE OR REPLACE VIEW vw_invoice_balance AS
SELECT
    i.invoice_id,
    i.customer_id,
    i.invoice_date,
    i.due_date,
    i.invoice_amount,
    COALESCE(pt.total_paid, 0) AS total_paid,
    LEAST(i.invoice_amount, COALESCE(pt.total_paid, 0)) AS applied_payment,
    GREATEST(i.invoice_amount - COALESCE(pt.total_paid, 0), 0) AS outstanding_amount,
    pt.last_payment_date,
    CASE
        WHEN COALESCE(pt.total_paid, 0) = 0 THEN 'Unpaid'
        WHEN COALESCE(pt.total_paid, 0) < i.invoice_amount THEN 'Partially Paid'
        ELSE 'Paid'
    END AS calculated_payment_status
FROM invoices i
LEFT JOIN vw_payment_totals pt ON i.invoice_id = pt.invoice_id;

-- date used for aging (latest date in the data, so old data still works)
-- use CURDATE() instead if you want today's date
SET @as_of_date = GREATEST(
    (SELECT MAX(invoice_date) FROM invoices),
    (SELECT MAX(payment_date) FROM payments)
);


-- ------------------------------------------------------------
-- 1. BUSINESS SNAPSHOT
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS total_invoices,
    COUNT(DISTINCT customer_id) AS customers_with_invoices,
    ROUND(SUM(invoice_amount), 2) AS total_invoiced,
    ROUND(AVG(invoice_amount), 2) AS average_invoice_value
FROM invoices;

-- ------------------------------------------------------------
-- 2. PAYMENT SUMMARY
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS payment_transactions,
    COUNT(DISTINCT invoice_id) AS invoices_with_payments,
    ROUND(SUM(payment_amount), 2) AS total_cash_collected,
    ROUND(AVG(payment_amount), 2) AS average_payment
FROM payments;

-- ------------------------------------------------------------
-- 3. INVOICE-LEVEL PAYMENT BALANCE
-- ------------------------------------------------------------
SELECT
    invoice_id,
    customer_id,
    invoice_date,
    due_date,
    invoice_amount,
    total_paid,
    ROUND(outstanding_amount, 2) AS outstanding_amount,
    calculated_payment_status
FROM vw_invoice_balance
ORDER BY invoice_id
LIMIT 100;

-- ------------------------------------------------------------
-- 4. INVOICE STATUS BREAKDOWN
-- ------------------------------------------------------------
SELECT
    calculated_payment_status,
    COUNT(*) AS invoice_count,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_invoices,
    ROUND(SUM(invoice_amount), 2) AS invoiced_value,
    ROUND(SUM(outstanding_amount), 2) AS outstanding_value
FROM vw_invoice_balance
GROUP BY calculated_payment_status
ORDER BY invoice_count DESC;

-- ------------------------------------------------------------
-- 5. TOTAL OUTSTANDING RECEIVABLES
-- ------------------------------------------------------------
SELECT ROUND(SUM(outstanding_amount), 2) AS total_outstanding_receivables
FROM vw_invoice_balance;

-- ------------------------------------------------------------
-- 6. COLLECTION RATE
-- ------------------------------------------------------------
SELECT
    ROUND(SUM(invoice_amount), 2) AS total_invoiced,
    ROUND(SUM(applied_payment), 2) AS collected_amount,
    ROUND(100 * SUM(applied_payment) / NULLIF(SUM(invoice_amount), 0), 2) AS collection_rate_pct
FROM vw_invoice_balance;

-- ------------------------------------------------------------
-- 7. MONTHLY INVOICED VALUE
-- ------------------------------------------------------------
SELECT
    DATE_FORMAT(invoice_date, '%Y-%m') AS invoice_month,
    COUNT(*) AS invoice_count,
    ROUND(SUM(invoice_amount), 2) AS monthly_invoiced_value
FROM invoices
GROUP BY DATE_FORMAT(invoice_date, '%Y-%m')
ORDER BY invoice_month;

-- ------------------------------------------------------------
-- 8. MONTH-OVER-MONTH CHANGE
-- ------------------------------------------------------------
WITH monthly AS (
    SELECT
        DATE_FORMAT(invoice_date, '%Y-%m') AS invoice_month,
        SUM(invoice_amount) AS invoiced_value
    FROM invoices
    GROUP BY DATE_FORMAT(invoice_date, '%Y-%m')
),
with_previous AS (
    SELECT
        invoice_month,
        invoiced_value,
        LAG(invoiced_value) OVER (ORDER BY invoice_month) AS previous_month_value
    FROM monthly
)
SELECT
    invoice_month,
    ROUND(invoiced_value, 2) AS invoiced_value,
    ROUND(previous_month_value, 2) AS previous_month_value,
    ROUND(invoiced_value - previous_month_value, 2) AS change_amount,
    ROUND(100 * (invoiced_value - previous_month_value) /
          NULLIF(previous_month_value, 0), 2) AS change_pct
FROM with_previous
ORDER BY invoice_month;

-- ------------------------------------------------------------
-- 9. MONTHLY CASH COLLECTIONS
-- ------------------------------------------------------------
SELECT
    DATE_FORMAT(payment_date, '%Y-%m') AS payment_month,
    COUNT(*) AS payment_transactions,
    ROUND(SUM(payment_amount), 2) AS cash_collected
FROM payments
GROUP BY DATE_FORMAT(payment_date, '%Y-%m')
ORDER BY payment_month;

-- ------------------------------------------------------------
-- 10. RUNNING TOTAL OF COLLECTIONS
-- ------------------------------------------------------------
WITH monthly_cash AS (
    SELECT
        DATE_FORMAT(payment_date, '%Y-%m') AS payment_month,
        SUM(payment_amount) AS cash_collected
    FROM payments
    GROUP BY DATE_FORMAT(payment_date, '%Y-%m')
)
SELECT
    payment_month,
    ROUND(cash_collected, 2) AS cash_collected,
    ROUND(SUM(cash_collected) OVER (ORDER BY payment_month), 2) AS running_total
FROM monthly_cash
ORDER BY payment_month;

-- ------------------------------------------------------------
-- 11. COLLECTIONS BY PAYMENT METHOD
-- ------------------------------------------------------------
SELECT
    payment_method,
    COUNT(*) AS transaction_count,
    ROUND(SUM(payment_amount), 2) AS amount_collected,
    ROUND(AVG(payment_amount), 2) AS average_transaction,
    ROUND(100 * SUM(payment_amount) / SUM(SUM(payment_amount)) OVER (), 2) AS pct_of_total
FROM payments
GROUP BY payment_method
ORDER BY amount_collected DESC;

-- ------------------------------------------------------------
-- 12. CUSTOMER-WISE INVOICED, PAID AND OUTSTANDING
-- ------------------------------------------------------------
WITH customer_balances AS (
    SELECT
        customer_id,
        SUM(invoice_amount) AS invoiced,
        SUM(applied_payment) AS paid,
        SUM(outstanding_amount) AS outstanding
    FROM vw_invoice_balance
    GROUP BY customer_id
)
SELECT
    c.customer_id,
    c.customer_name,
    c.region,
    c.customer_segment,
    ROUND(cb.invoiced, 2) AS invoiced,
    ROUND(cb.paid, 2) AS paid,
    ROUND(cb.outstanding, 2) AS outstanding,
    DENSE_RANK() OVER (ORDER BY cb.outstanding DESC) AS outstanding_rank
FROM customer_balances cb
JOIN customers c ON cb.customer_id = c.customer_id
ORDER BY outstanding_rank;

-- ------------------------------------------------------------
-- 13. TOP 10 CUSTOMERS BY INVOICED VALUE
-- ------------------------------------------------------------
SELECT
    c.customer_id,
    c.customer_name,
    ROUND(SUM(i.invoice_amount), 2) AS invoiced_value
FROM customers c
JOIN invoices i ON c.customer_id = i.customer_id
GROUP BY c.customer_id, c.customer_name
ORDER BY invoiced_value DESC
LIMIT 10;

-- ------------------------------------------------------------
-- 14. TOP 10 CUSTOMERS BY OUTSTANDING BALANCE
-- ------------------------------------------------------------
SELECT
    c.customer_id,
    c.customer_name,
    c.region,
    ROUND(SUM(b.outstanding_amount), 2) AS outstanding
FROM vw_invoice_balance b
JOIN customers c ON b.customer_id = c.customer_id
GROUP BY c.customer_id, c.customer_name, c.region
ORDER BY outstanding DESC
LIMIT 10;

-- ------------------------------------------------------------
-- 15. RECEIVABLES BY REGION
-- ------------------------------------------------------------
SELECT
    c.region,
    COUNT(DISTINCT c.customer_id) AS customers,
    ROUND(SUM(b.invoice_amount), 2) AS invoiced,
    ROUND(SUM(b.applied_payment), 2) AS collected,
    ROUND(SUM(b.outstanding_amount), 2) AS outstanding,
    ROUND(100 * SUM(b.applied_payment) / NULLIF(SUM(b.invoice_amount), 0), 2) AS collection_rate_pct
FROM vw_invoice_balance b
JOIN customers c ON b.customer_id = c.customer_id
GROUP BY c.region
ORDER BY outstanding DESC;

-- ------------------------------------------------------------
-- 16. RECEIVABLES BY CUSTOMER SEGMENT
-- ------------------------------------------------------------
SELECT
    c.customer_segment,
    COUNT(DISTINCT c.customer_id) AS customers,
    ROUND(SUM(b.invoice_amount), 2) AS invoiced,
    ROUND(SUM(b.applied_payment), 2) AS collected,
    ROUND(SUM(b.outstanding_amount), 2) AS outstanding,
    ROUND(100 * SUM(b.applied_payment) / NULLIF(SUM(b.invoice_amount), 0), 2) AS collection_rate_pct
FROM vw_invoice_balance b
JOIN customers c ON b.customer_id = c.customer_id
GROUP BY c.customer_segment
ORDER BY outstanding DESC;

-- ------------------------------------------------------------
-- 17. AGING SUMMARY
-- ------------------------------------------------------------
SELECT
    CASE
        WHEN DATEDIFF(@as_of_date, due_date) <= 0 THEN '0 - Not yet due'
        WHEN DATEDIFF(@as_of_date, due_date) <= 30 THEN '1 - 1-30 days'
        WHEN DATEDIFF(@as_of_date, due_date) <= 60 THEN '2 - 31-60 days'
        WHEN DATEDIFF(@as_of_date, due_date) <= 90 THEN '3 - 61-90 days'
        ELSE '4 - 90+ days'
    END AS aging_bucket,
    COUNT(*) AS open_invoices,
    ROUND(SUM(outstanding_amount), 2) AS outstanding_amount,
    ROUND(100 * SUM(outstanding_amount) / SUM(SUM(outstanding_amount)) OVER (), 2) AS pct_of_outstanding
FROM vw_invoice_balance
WHERE outstanding_amount > 0
GROUP BY aging_bucket
ORDER BY aging_bucket;

-- ------------------------------------------------------------
-- 18. AGING BY CUSTOMER
-- ------------------------------------------------------------
SELECT
    c.customer_id,
    c.customer_name,
    ROUND(SUM(CASE WHEN DATEDIFF(@as_of_date, b.due_date) <= 0 THEN b.outstanding_amount ELSE 0 END), 2) AS not_yet_due,
    ROUND(SUM(CASE WHEN DATEDIFF(@as_of_date, b.due_date) BETWEEN 1 AND 30 THEN b.outstanding_amount ELSE 0 END), 2) AS days_1_30,
    ROUND(SUM(CASE WHEN DATEDIFF(@as_of_date, b.due_date) BETWEEN 31 AND 60 THEN b.outstanding_amount ELSE 0 END), 2) AS days_31_60,
    ROUND(SUM(CASE WHEN DATEDIFF(@as_of_date, b.due_date) BETWEEN 61 AND 90 THEN b.outstanding_amount ELSE 0 END), 2) AS days_61_90,
    ROUND(SUM(CASE WHEN DATEDIFF(@as_of_date, b.due_date) > 90 THEN b.outstanding_amount ELSE 0 END), 2) AS days_90_plus,
    ROUND(SUM(b.outstanding_amount), 2) AS total_outstanding
FROM vw_invoice_balance b
JOIN customers c ON b.customer_id = c.customer_id
WHERE b.outstanding_amount > 0
GROUP BY c.customer_id, c.customer_name
ORDER BY total_outstanding DESC;

-- ------------------------------------------------------------
-- 19. 20 MOST OVERDUE OPEN INVOICES
-- ------------------------------------------------------------
SELECT
    b.invoice_id,
    c.customer_name,
    b.due_date,
    DATEDIFF(@as_of_date, b.due_date) AS days_overdue,
    ROUND(b.outstanding_amount, 2) AS outstanding_amount,
    b.calculated_payment_status
FROM vw_invoice_balance b
JOIN customers c ON b.customer_id = c.customer_id
WHERE b.outstanding_amount > 0
  AND DATEDIFF(@as_of_date, b.due_date) > 0
ORDER BY days_overdue DESC, outstanding_amount DESC
LIMIT 20;

-- ------------------------------------------------------------
-- 20. OVERDUE SHARE OF TOTAL RECEIVABLES
-- ------------------------------------------------------------
SELECT
    ROUND(SUM(outstanding_amount), 2) AS total_outstanding,
    ROUND(SUM(CASE WHEN DATEDIFF(@as_of_date, due_date) > 0
                   THEN outstanding_amount ELSE 0 END), 2) AS overdue_amount,
    ROUND(100 * SUM(CASE WHEN DATEDIFF(@as_of_date, due_date) > 0
                         THEN outstanding_amount ELSE 0 END)
          / NULLIF(SUM(outstanding_amount), 0), 2) AS overdue_pct
FROM vw_invoice_balance;

-- ------------------------------------------------------------
-- 21. ON-TIME VS LATE PAYMENTS (paid invoices only)
-- ------------------------------------------------------------
SELECT
    COUNT(*) AS paid_invoices,
    SUM(CASE WHEN last_payment_date <= due_date THEN 1 ELSE 0 END) AS paid_on_time,
    SUM(CASE WHEN last_payment_date > due_date THEN 1 ELSE 0 END) AS paid_late,
    ROUND(100 * SUM(CASE WHEN last_payment_date > due_date THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_payment_pct,
    ROUND(AVG(DATEDIFF(last_payment_date, due_date)), 1) AS avg_days_vs_due_date
FROM vw_invoice_balance
WHERE calculated_payment_status = 'Paid';

-- ------------------------------------------------------------
-- 22. AVERAGE DAYS TO PAY BY INVOICE MONTH
-- ------------------------------------------------------------
SELECT
    DATE_FORMAT(invoice_date, '%Y-%m') AS invoice_month,
    COUNT(*) AS paid_invoices,
    ROUND(AVG(DATEDIFF(last_payment_date, invoice_date)), 1) AS avg_days_to_pay
FROM vw_invoice_balance
WHERE calculated_payment_status = 'Paid'
GROUP BY DATE_FORMAT(invoice_date, '%Y-%m')
ORDER BY invoice_month;

-- ------------------------------------------------------------
-- 23. SLOWEST PAYING CUSTOMERS
-- ------------------------------------------------------------
SELECT
    c.customer_id,
    c.customer_name,
    COUNT(*) AS paid_invoices,
    ROUND(AVG(DATEDIFF(b.last_payment_date, b.due_date)), 1) AS avg_days_past_due,
    ROUND(100 * SUM(CASE WHEN b.last_payment_date > b.due_date THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_pct,
    RANK() OVER (ORDER BY AVG(DATEDIFF(b.last_payment_date, b.due_date)) DESC) AS slowness_rank
FROM vw_invoice_balance b
JOIN customers c ON b.customer_id = c.customer_id
WHERE b.calculated_payment_status = 'Paid'
GROUP BY c.customer_id, c.customer_name
HAVING COUNT(*) >= 3
ORDER BY slowness_rank
LIMIT 20;

-- ------------------------------------------------------------
-- 24. DAYS SALES OUTSTANDING (DSO)
--     outstanding / total invoiced * days in period
-- ------------------------------------------------------------
SELECT
    ROUND(SUM(outstanding_amount), 2) AS outstanding_receivables,
    ROUND(SUM(invoice_amount), 2) AS total_invoiced,
    DATEDIFF(MAX(invoice_date), MIN(invoice_date)) + 1 AS days_in_period,
    ROUND(SUM(outstanding_amount) / NULLIF(SUM(invoice_amount), 0)
          * (DATEDIFF(MAX(invoice_date), MIN(invoice_date)) + 1), 1) AS dso_days
FROM vw_invoice_balance;

-- ------------------------------------------------------------
-- 25. DUPLICATE INVOICE CHECK
-- ------------------------------------------------------------
SELECT
    invoice_id,
    COUNT(*) AS duplicate_count
FROM invoices
GROUP BY invoice_id
HAVING COUNT(*) > 1;

-- ------------------------------------------------------------
-- 26. PAYMENTS WITH NO MATCHING INVOICE
-- ------------------------------------------------------------
SELECT p.*
FROM payments p
LEFT JOIN invoices i ON p.invoice_id = i.invoice_id
WHERE i.invoice_id IS NULL;

-- ------------------------------------------------------------
-- 27. OVERPAID INVOICES
-- ------------------------------------------------------------
SELECT
    invoice_id,
    invoice_amount,
    total_paid,
    ROUND(total_paid - invoice_amount, 2) AS overpaid_by
FROM vw_invoice_balance
WHERE total_paid > invoice_amount
ORDER BY overpaid_by DESC;

-- ------------------------------------------------------------
-- 28. INVALID DATES AND AMOUNTS
-- ------------------------------------------------------------
SELECT 'due date before invoice date' AS issue, COUNT(*) AS records
FROM invoices WHERE due_date < invoice_date
UNION ALL
SELECT 'payment before invoice date', COUNT(*)
FROM payments p JOIN invoices i ON p.invoice_id = i.invoice_id
WHERE p.payment_date < i.invoice_date
UNION ALL
SELECT 'invoice amount <= 0', COUNT(*)
FROM invoices WHERE invoice_amount <= 0
UNION ALL
SELECT 'payment amount <= 0', COUNT(*)
FROM payments WHERE payment_amount <= 0;
