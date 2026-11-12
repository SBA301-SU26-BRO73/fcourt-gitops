# Gateway routes

Vietnamese notes, moved from the README.


Gateway sở hữu Ingress duy nhất (path `/`). Tham chiếu route (từ controller trong `fcourt-backend`, cộng `/devices`); không route `/api/internal/**`, `/actuator/**` của service khác, `/.well-known/jwks.json`, gRPC của slot-hold-engine.

| Path | Service | Port |
|---|---|---|
| `/api/auth`, `/api/super-admin/court-admins`, `/api/super-admin/users`, `/api/super-admin/stats/accounts`, `/api/super-admin/stats/owner-names` | auth-service | 8081 |
| `/api/subscriptions`, `/api/subscription-plans`, `/api/court-types`, `/api/super-admin/stats/saas-revenue` | subscription-service | 8082 |
| `/api/public/branches/*` (chi tiết, `/images`, `/courts`), `/api/admin/branches`, `/api/admin/courts`, `/api/admin/time-slot-templates`, `/api/staff/branches`, `/api/staff/courts` | facility-service | 8083 |
| `/api/admin/dashboard`, `/api/super-admin/dashboard` | reporting-service | 8084 |
| `/api/public/branches` (list), `/api/public/branches/*/reviews`, `/api/public/courts`, `/api/reviews`, `/api/admin/reviews` | discovery-service | 8085 |
| `/api/vouchers`, `/api/admin/vouchers` | voucher-service | 8086 |
| `/api/bookings/hold-slots` | slot-hold-engine | 8087 |
| `/api/bookings`, `/api/admin/bookings`, `/ws-fcourt` (WebSocket/STOMP) | booking-service | 8088 |
| `/api/payments`, `/api/refunds`, `/api/admin/payments`, `/api/admin/refunds` | payment-service | 8089 |
| `/api/staff/schedule`, `/check-in`, `/offline`, `/me`, `/walk-in`, `/bookings`, `/api/admin/staff` | staff-operations-service | 8090 |
| `/devices` | notification-service | 8091 |
| `/api/staff/pos`, `/api/admin/pos` | pos-retail-service | 8092 |

Thứ tự ưu tiên: Spring Cloud Gateway lấy route khớp đầu tiên, nên `/api/bookings/hold-slots` phải đứng trước `/api/bookings`, và các route reviews/list của discovery phải đứng trước wildcard `/api/public/branches/*` của facility. `/ws-fcourt` cần WebSocket upgrade tới booking-service; Ingress đặt `idle_timeout.timeout_seconds=3600` và `deregistration_delay.timeout_seconds=60`. `pos-retail-service` dùng 8092 để tránh trùng 8091 của notification-service.
