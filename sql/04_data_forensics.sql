-- Data-forensics checks
SELECT payment_id, COUNT(*) AS n FROM payments GROUP BY payment_id HAVING n>1 ORDER BY n DESC;
SELECT call_id, COUNT(*) AS n FROM calls GROUP BY call_id HAVING n>1 ORDER BY n DESC;
SELECT COUNT(*) AS status_time_conflicts FROM account_status_history WHERE recorded_at < event_at;
SELECT COUNT(*) AS call_vendor_timezone_conflicts FROM calls c JOIN vendor_telephony v ON c.vendor_id=v.vendor_id WHERE c.timezone<>v.timezone;
SELECT employee_code, COUNT(DISTINCT agent_id) AS agent_ids FROM agents GROUP BY employee_code HAVING agent_ids>1;
SELECT COUNT(*) AS orphan_accounts FROM accounts a LEFT JOIN borrowers b USING(borrower_id) WHERE b.borrower_id IS NULL;
