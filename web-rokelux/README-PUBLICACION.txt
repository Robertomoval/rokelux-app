ROKELUX — SITIO WEB INSTITUCIONAL

Contenido de esta carpeta:
- index.html: página completa, adaptable a móvil y escritorio.
- site.css y site.js: estilos y funciones de la página.
- logo.png: logotipo de ROKELUX.
- rokel.png: mascota oficial ROKEL, usada en la portada.
- El logotipo conserva sus colores originales y se enmarca con un borde verde neón para integrarlo visualmente al tema oscuro.

FUNCIONES
- Navegación adaptable para teléfonos.
- Enlaces de correo y teléfono.
- Botón flotante de WhatsApp.
- Formulario de cotización que abre WhatsApp con el mensaje preparado.
- Enlace de acceso al portal actual de clientes.
- Metadatos básicos para buscadores y compartir la página.
- El formulario no guarda ni envía datos a un servidor: los deja listos en WhatsApp.

PUBLICACIÓN COMO SITIO ESTÁTICO
La carpeta completa se publica como sitio estático. No requiere instalar paquetes ni configurar un servidor.
En Render, elegir New > Static Site, conectar un repositorio con esta carpeta, dejar Build Command vacío y usar `.` como Publish Directory si esta carpeta es la raíz del repositorio.

DOMINIO Y CORREO
La dirección propuesta es https://www.rokeluxec.com/ y la aplicación de clientes conserva https://rokelux-app.vercel.app/.
Al enlazar el dominio, cambiar únicamente los registros web indicados por Render. No cambiar servidores DNS, registros MX, TXT, SPF, DKIM ni DMARC: protegen el correo.
La publicación pública aún requiere enlazar esta carpeta a un repositorio de Git y agregar el dominio en el panel de hosting. No se realizaron cambios DNS ni se publicaron cambios en la aplicación.
