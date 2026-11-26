
Accounts Receivable SQL Analysis

SQL analysis of accounts receivable data: invoicing trends, cash collections, outstanding balances and customer performance, built in MySQL.

  Project Overview

Accounts receivable (AR) shows how much money customers owe a business and how well that money is being collected. This project uses SQL to answer the core questions a finance team asks about receivables, starting with data quality checks and moving through business metrics, trends and customer-level analysis.

Business Questions Answered
How many invoices were issued, to how many customers, and for what total value?
How much cash has been collected, and through which payment methods?
What is the total outstanding receivable balance?
What percentage of invoiced value has been collected (collection rate)?
How does invoiced value change month over month?
How much does each customer owe, and who are the top customers by invoiced value?
Are there data quality issues such as duplicate invoice IDs?
    Database Structure
    
    The database accounts_receivable_db contains three tables:

Table	Key columns	Description
customers	customer_id, customer_name, region, customer_segment	One row per customer
invoices	invoice_id, customer_id, invoice_date, due_date, invoice_amount	One row per invoice issued
payments	invoice_id, payment_date, payment_amount, payment_method	One row per payment received

Relationships: customers 1 → many invoices 1 → many payments. An invoice can have several payments (partial payments).

  SQL Skills Demonstrated
Aggregations: COUNT, SUM, AVG, GROUP BY, HAVING
Common Table Expressions (CTEs): reusable invoice-level payment totals
Window functions: LAG() for month-over-month change
Joins: LEFT JOIN to keep unpaid invoices, JOIN to enrich with customer details
Conditional logic: CASE to classify invoices as Paid, Partially Paid or Unpaid
Safe calculations: COALESCE, NULLIF, LEAST, GREATEST to handle missing payments, divide-by-zero and overpayments
Date handling: DATE_FORMAT for monthly trends
Data quality checks: duplicate detection
Analysis Sections
    #	Analysis	Purpose
0	Data quality check	Confirm invoice_id is unique before analysis
1	Business snapshot	Invoice count, customers, total and average invoice value
2	Payment summary	Transactions, total cash collected, average payment
3	Invoice-level balance	Paid, outstanding and status per invoice
4	Total outstanding receivables	Overall amount still owed
5	Collection rate	Collected amount as a percentage of invoiced amount
6	Monthly invoiced value	Invoicing volume and value by month
7	Month-over-month change	Growth or decline using LAG()
8	Monthly cash collections	Cash received by month
9	Collections by payment method	Which methods bring in the most cash
10	Customer balances	Invoiced, paid and outstanding per customer
11	Top 10 customers	Highest customers by invoiced value
Key Findings
Total invoiced: 2,100,187.50 across 900 invoices from 120 customers
Total outstanding receivables: 423,397.50, about 20.2% of the total invoiced value
Collection rate: 79.84%, meaning roughly 4 out of every 5 invoiced units of currency have been collected
Top payment method: Credit Card, the largest source of cash collected
Top customer by invoiced value: Customer 091
Average invoice value: about 2,333.54 (total invoiced divided by 900 invoices)
Screenshots


Repository Structure
accounts-receivable-sql-analysis/
├── README.md
├── schema.sql          # table definitions
├── sample_data.sql     # sample or synthetic data
├── ar_analysis.sql     # all analysis queries
└── screenshots/        # query result images
How to Run
Install MySQL 8.0 or later (window functions and CTEs require 8.0+).
Create the database and tables:
sql
SOURCE schema.sql;
Load the sample data:
sql
SOURCE sample_data.sql;
Run the analysis:
sql
SOURCE ar_analysis.sql;
Assumptions and Limitations
Payments above the invoice amount are capped when calculating outstanding balances and collection rate, so overpayments do not create negative balances.
Collection rate includes invoices that are not yet due, so it may understate collection performance.
Month-over-month change compares against the previous month that has data, not necessarily the previous calendar month.
The data is synthetic/sample data and does not represent a real company.
Future Improvements
Accounts receivable aging report (current, 1-30, 31-60, 61-90, 90+ days overdue)
Days Sales Outstanding (DSO)
Overdue amount by customer, region and segment
Dashboard in Power BI or Tableau
