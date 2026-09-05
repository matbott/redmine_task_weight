# ⚖️ Redmine Task Weight Plugin

> **Author:** `matbott & 🤖`<br>
> **Repository:** [github.com/matbott/redmine_task_weight](https://github.com/matbott/redmine_task_weight)<br>
> **Version:** 1.3.3<br>
> **Compatibility:** Redmine 5.x, 6.x, and 7.x (Rails 6, 7, and 8; Zeitwerk compatible)

---

<img width="1521" height="885" alt="Task Weight settings" src="https://github.com/user-attachments/assets/c50a26b0-7f4f-4a2c-bc26-c7fb61719810" />

<img width="1899" height="715" alt="Workload distribution report" src="https://github.com/user-attachments/assets/14ff9b73-62f8-4efe-8f4c-263869cf45db" />

## 📌 Description

Redmine Task Weight automatically calculates an issue's **workload weight (score)**. It uses a multiplicative formula based on configurable per-project attributes: tracker, category, priority, and an optional List or Numeric custom field.

It is designed for team workload distribution, capacity planning, and metrics dashboards such as **Grafana**, which can query the calculated values directly from the Redmine database.

## ✨ Features

1. **Multiplicative formula**

   ```text
   Final Weight = Tracker Factor × Category Factor × Priority Factor × Extra Custom Field Factor
   ```

2. **List and numeric custom field support:** assign multipliers to list options (for example, *Complexity: Low = 0.8, Medium = 1.0, High = 1.8, Critical = 2.5*) or use a positive numeric value directly.
3. **Live preview:** authorized users see the calculated weight update in real time while editing an issue.
4. **Server-side calculation:** the plugin calculates and stores the weight when an issue is saved, even when the target custom field is hidden from regular users.
5. **Manual overrides:** an explicitly entered weight is preserved instead of being overwritten by later calculations.
6. **Per-project configuration:** configure calculation rules centrally under *Administration → Plugins → Configure*.
7. **Three calculation modes:** multiplicative formula, priority only, or fully manual.
8. **Workload distribution report:** a project tab summarizes open workload and completed score by assignee.

## 🚀 Installation

Clone the plugin into your Redmine plugins directory:

```bash
cd /path/to/redmine/plugins
git clone https://github.com/matbott/redmine_task_weight.git
```

Restart Redmine. For example, a systemd installation might use:

```bash
sudo systemctl restart redmine
```

No database migration is required. On startup, the plugin creates a hidden float custom field named **Task Weight** when no compatible weight field exists.

## ⚙️ Configuration

1. Open **Administration → Plugins → Redmine Task Weight Plugin → Configure**.
2. Select a project.
3. Select a calculation mode: *Multiplicative Formula*, *Priority Only*, or *Manual*.
4. Set factors for trackers, categories, priorities, and, optionally, another custom field.
5. Select a different target custom field if you do not want to use the automatically managed **Task Weight** field.
6. Save the settings.
7. Open **Project Settings → Modules** and enable **Task Weight** for each project that should use calculation and reporting.

The plugin continues to recognize the legacy Spanish field names **Peso de la Tarea** and **Peso**, so existing installations remain compatible.

## 📊 Database and Grafana Integration

The calculated value is stored in Redmine's `custom_values` table under the configured target custom field. By default, that field is named **Task Weight**.

Example PostgreSQL query for Grafana:

```sql
SELECT
  u.login AS user_login,
  CONCAT(u.firstname, ' ', u.lastname) AS user_name,
  p.identifier AS project,
  i.id AS issue_id,
  i.subject,
  s.name AS status,
  cv.value::float AS task_weight,
  i.created_on
FROM issues i
JOIN projects p ON p.id = i.project_id
JOIN issue_statuses s ON s.id = i.status_id
LEFT JOIN users u ON u.id = i.assigned_to_id
JOIN custom_values cv
  ON cv.customized_type = 'Issue'
 AND cv.customized_id = i.id
JOIN custom_fields cf
  ON cf.id = cv.custom_field_id
 AND cf.name = 'Task Weight'
WHERE s.is_closed = FALSE;
```

If you selected another target custom field, update the `cf.name` condition accordingly.

## 📄 License

MIT License. Created by `matbott & 🤖`.
