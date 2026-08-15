# ⚖️ Redmine Task Weight Plugin

> **Author:** `matbott & 🤖`  
> **Repository:** [https://github.com/matbott/redmine_task_weight](https://github.com/matbott/redmine_task_weight)  
> **Version:** 1.3.0  
> **Compatibility:** Redmine 4.x / 5.x / 6.x (Rails 6/7/8 & Zeitwerk compatible)

---

## 📌 Description / Descripción

### 🇪🇸 Español
**Redmine Task Weight Plugin** es un plugin para Redmine diseñado para calcular automáticamente el **peso (Score) de carga de trabajo** de cada tarea. Utiliza una **Fórmula Factorial Multiplicativa** basada en atributos configurables por proyecto (Tracker, Categoría, Prioridad y Campos Personalizados de Texto/Lista o Numéricos).

Es ideal para gestionar la distribución de carga de equipo, estimar esfuerzo y alimentar tableros de métricas en **Grafana** consultando directamente la base de datos de Redmine.

### 🇬🇧 English
**Redmine Task Weight Plugin** is a Redmine plugin engineered to automatically calculate issue **workload weight (Score)**. It uses a **Multiplicative Factorial Formula** based on configurable per-project attributes (Tracker, Category, Priority, and optional List/Numeric Custom Fields).

Ideal for team workload distribution, capacity planning, and feeding metric dashboards in **Grafana** by querying the Redmine database directly.

---

## ✨ Features / Características principales

### 🇪🇸 Español
1. **Fórmula Factorial Multiplicativa:**
   `Peso Final = Factor Tracker * Factor Categoría * Factor Prioridad * Factor Campo Extra`
2. **Soporte para Campos Personalizados de Texto/Lista:** Asigna factores multiplicadores a opciones de texto (ej. *Complejidad: Baja=0.8, Media=1.0, Alta=1.8, Crítica=2.5*).
3. **Cálculo "En Vivo" (JavaScript Preview):** Actualización en tiempo real en la pantalla de edición del ticket para roles con visibilidad del campo.
4. **Cálculo Silencioso en Servidor:** Si el campo está oculto para usuarios comunes (`visible: false`), el servidor calcula y guarda el peso automáticamente al guardar la tarea.
5. **Respeto de Edición Manual:** Si un usuario autorizado modifica manualmente el valor del peso, el sistema detecta el cambio y respeta el valor manual.
6. **Administración Global sin Conflictos:** Panel de configuración centralizado en *Administración -> Plugins -> Configurar* con selector de proyecto, evitando conflictos de parcheo con otros plugins (ej. RedmineUp CMS).
7. **Reporte de Distribución de Carga:** Pestaña de reporte por proyecto que muestra el resumen y porcentaje de carga de trabajo pendiente por usuario asignado.

### 🇬🇧 English
1. **Multiplicative Factorial Formula:**
   `Final Weight = Tracker Factor * Category Factor * Priority Factor * Extra Custom Field Factor`
2. **Text/List Custom Field Support:** Assign weight factors to text list options (e.g. *Complexity: Low=0.8, Medium=1.0, High=1.8, Critical=2.5*).
3. **Real-Time Live UI Preview (JavaScript):** Updates weight live on the issue editing form for authorized roles.
4. **Silent Server-Side Processing:** If the custom field is hidden from developers (`visible: false`), the backend automatically calculates and persists the weight upon saving.
5. **Smart Manual Override:** If an authorized user manually enters a custom weight value, the system respects the manual entry and avoids overwriting it.
6. **Zero-Conflict Global Administration:** Centralized configuration panel in *Administration -> Plugins -> Configure* with project selector dropdown, avoiding monkey-patch conflicts with third-party plugins (e.g. RedmineUp CMS).
7. **Workload Distribution Report:** Built-in project tab displaying workload summary and percentage distribution per assignee.

---

## 🚀 Installation / Instalación

```bash
cd /path/to/redmine/plugins
git clone https://github.com/matbott/redmine_task_weight.git
```

Restart your Redmine server / Reiniciá tu servidor de Redmine:
```bash
# Example for Systemd / Puma / Passenger:
sudo systemctl restart redmine
```

---

## ⚙️ Configuration / Configuración

### 🇪🇸 Español
1. Dirígete a **Administración -> Plugins -> Redmine Task Weight Plugin -> Configurar**.
2. Selecciona el proyecto deseado en el selector desplegable.
3. Configura el modo de cálculo (*Fórmula Factorial* o *Por Prioridad*).
4. Asigna los factores deseados a Trackers, Categorías, Prioridades y Campos Personalizados adicionales.
5. Guarda los cambios.
6. En tu proyecto, habilita el módulo **"Peso de Tareas"** en *Configuración del proyecto -> Módulos*.

### 🇬🇧 English
1. Go to **Administration -> Plugins -> Redmine Task Weight Plugin -> Configure**.
2. Select your target project from the dropdown.
3. Choose the calculation mode (*Factorial Formula* or *By Priority*).
4. Set weight factors for Trackers, Categories, Priorities, and optional Custom Fields.
5. Save changes.
6. Enable the **"Task Weight"** module under *Project Settings -> Modules*.

---

## 📊 Database & Grafana Integration / Integración con Grafana

The calculated weight is automatically stored in Redmine's `custom_values` table under the custom field **"Peso de la Tarea"**.

Example SQL Query for Grafana:
```sql
SELECT 
  u.login AS user,
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
JOIN custom_values cv ON cv.customized_type = 'Issue' AND cv.customized_id = i.id
JOIN custom_fields cf ON cf.id = cv.custom_field_id AND cf.name = 'Peso de la Tarea'
WHERE s.is_closed = FALSE;
```

---

## 📄 License / Licencia

MIT License - Created by `matbott & 🤖`.
