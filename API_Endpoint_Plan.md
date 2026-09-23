# RaceDay – API Endpoint Plan

**Module:** PROG6212 – Programming 2B  |  **Part 1:** System Planning
**API style:** RESTful JSON API, ASP.NET Core Web API (Part 2)
**Base route:** `/api`

## Conventions

| Item | Decision |
|---|---|
| Authentication | Session-based. `POST /api/auth/login` creates a server-side session and returns a session cookie. The session stores `UserId` and `Role`, which every protected endpoint reads. |
| Roles | `Organiser` and `Participant`. The role is chosen at registration and validated against the `Roles` table. No other role (e.g. Admin) can be self-assigned. |
| Role Required values | **None** = public · **Any** = any logged-in user · **Organiser** / **Participant** = that role only · **(owner)** = the user must also own the resource (e.g. the Organiser who created the event) |
| Standard failures | `401 Unauthorized` = no valid session · `403 Forbidden` = logged in but wrong role or not the owner · `400 Bad Request` = validation failed · `404 Not Found` = resource does not exist · `409 Conflict` = request clashes with existing data |
| Passwords | Never returned by any endpoint. Stored only as a BCrypt hash. |
| Route IDs | Numeric IDs use the `{id:int}` route constraint so `/api/events/mine` does not clash with `/api/events/{id}`. |

---

## 1. Authentication

| HTTP Method | Route | Description | Role Required | Request Body | Expected Response |
|---|---|---|---|---|---|
| POST | `/api/auth/register` | Creates a new user account with the chosen role so the person can log in to RaceDay. | None | `{ firstName, lastName, email, password, phoneNumber, dateOfBirth, gender, role }` (role = "Organiser" or "Participant") | **201 Created** – new user profile (no password) · **400 Bad Request** – missing/invalid fields, weak password or invalid role · **409 Conflict** – email already registered |
| POST | `/api/auth/login` | Verifies the email and password hash, then starts a session holding the user's ID and role. | None | `{ email, password }` | **200 OK** – `{ userId, fullName, role }` plus session cookie · **400 Bad Request** – missing fields · **401 Unauthorized** – incorrect email or password |
| POST | `/api/auth/logout` | Ends the current session so the cookie can no longer be used. | Any | None | **204 No Content** – session cleared · **401 Unauthorized** – not logged in |
| GET | `/api/auth/session` | Returns who is currently logged in, so the MVC front end (Part 3) can show the correct menu for each role. | Any | None | **200 OK** – `{ userId, fullName, role }` · **401 Unauthorized** – no active session |

## 2. User Profile

| HTTP Method | Route | Description | Role Required | Request Body | Expected Response |
|---|---|---|---|---|---|
| GET | `/api/users/me` | Returns the logged-in user's own profile details. | Any | None | **200 OK** – `{ userId, firstName, lastName, email, phoneNumber, dateOfBirth, gender, role, createdAt }` · **401 Unauthorized** |
| PUT | `/api/users/me` | Updates the logged-in user's own personal details (email and role cannot be changed here). | Any | `{ firstName, lastName, phoneNumber, dateOfBirth, gender }` | **200 OK** – updated profile · **400 Bad Request** – invalid data · **401 Unauthorized** |
| PUT | `/api/users/me/password` | Changes the logged-in user's password after confirming the current one. | Any | `{ currentPassword, newPassword }` | **204 No Content** – password changed · **400 Bad Request** – current password wrong or new password too weak · **401 Unauthorized** |

## 3. Event Types

| HTTP Method | Route | Description | Role Required | Request Body | Expected Response |
|---|---|---|---|---|---|
| GET | `/api/event-types` | Lists the allowed event types (Run, Walk, Cycle) used to fill dropdowns and filters. | None | None | **200 OK** – `[ { eventTypeId, typeName } ]` |

## 4. Events

| HTTP Method | Route | Description | Role Required | Request Body | Expected Response |
|---|---|---|---|---|---|
| GET | `/api/events` | Lists events, with optional filters `?type=Run&upcoming=true&location=Soweto`, so both roles can browse. | Any | None | **200 OK** – list of `{ eventId, name, eventDate, location, distanceKm, eventType, organiserName }` · **400 Bad Request** – invalid filter value · **401 Unauthorized** |
| GET | `/api/events/{id:int}` | Returns full details of one event, including its categories. | Any | None | **200 OK** – event with `categories[]` · **401 Unauthorized** · **404 Not Found** – event does not exist |
| GET | `/api/events/mine` | Lists only the events created by the logged-in Organiser (their dashboard). | Organiser | None | **200 OK** – list of the organiser's events · **401 Unauthorized** · **403 Forbidden** – not an Organiser |
| POST | `/api/events` | Creates a new event owned by the logged-in Organiser. | Organiser | `{ name, description, eventDate, location, latitude, longitude, distanceKm, eventTypeId }` | **201 Created** – created event with Location header · **400 Bad Request** – missing fields, date in the past, distance ≤ 0, or invalid eventTypeId · **401 Unauthorized** · **403 Forbidden** – not an Organiser |
| PUT | `/api/events/{id:int}` | Updates the details of an event the Organiser created. | Organiser (owner) | `{ name, description, eventDate, location, latitude, longitude, distanceKm, eventTypeId }` | **200 OK** – updated event · **400 Bad Request** – invalid data · **401 Unauthorized** · **403 Forbidden** – not the owner · **404 Not Found** |
| DELETE | `/api/events/{id:int}` | Deletes an event (and its categories) that has no enrolments yet. | Organiser (owner) | None | **204 No Content** – deleted · **401 Unauthorized** · **403 Forbidden** – not the owner · **404 Not Found** · **409 Conflict** – event already has enrolments |

## 5. Categories

| HTTP Method | Route | Description | Role Required | Request Body | Expected Response |
|---|---|---|---|---|---|
| GET | `/api/events/{eventId:int}/categories` | Lists the age or distance categories available for an event, so a Participant can choose one. | Any | None | **200 OK** – list of `{ categoryId, name, categoryType, minAge, maxAge, distanceKm, maxParticipants, spotsLeft }` · **401 Unauthorized** · **404 Not Found** – event does not exist |
| POST | `/api/events/{eventId:int}/categories` | Adds a new age or distance category to the Organiser's event. | Organiser (owner) | `{ name, categoryType, minAge, maxAge, distanceKm, maxParticipants }` (categoryType = "Age" or "Distance") | **201 Created** – created category · **400 Bad Request** – invalid type, minAge > maxAge, or missing values · **401 Unauthorized** · **403 Forbidden** – not the owner · **404 Not Found** – event does not exist · **409 Conflict** – category name already exists for this event |
| PUT | `/api/events/{eventId:int}/categories/{categoryId:int}` | Updates a category on the Organiser's event. | Organiser (owner) | `{ name, categoryType, minAge, maxAge, distanceKm, maxParticipants }` | **200 OK** – updated category · **400 Bad Request** · **401 Unauthorized** · **403 Forbidden** · **404 Not Found** – event or category not found · **409 Conflict** – duplicate name |
| DELETE | `/api/events/{eventId:int}/categories/{categoryId:int}` | Removes a category that nobody has enrolled in yet. | Organiser (owner) | None | **204 No Content** · **401 Unauthorized** · **403 Forbidden** · **404 Not Found** · **409 Conflict** – category has enrolments |

## 6. Event Enrolments

| HTTP Method | Route | Description | Role Required | Request Body | Expected Response |
|---|---|---|---|---|---|
| POST | `/api/events/{eventId:int}/enrolments` | Enters the logged-in Participant into an event in their selected category, recording the Participant–Event–Category link. | Participant | `{ categoryId }` | **201 Created** – `{ enrolmentId, eventName, categoryName, status, enrolledAt }` · **400 Bad Request** – category does not belong to this event, event date has passed, or participant's age is outside the category range · **401 Unauthorized** · **403 Forbidden** – not a Participant · **404 Not Found** – event or category not found · **409 Conflict** – already enrolled in this event or category is full |
| GET | `/api/enrolments/mine` | Lists all events the logged-in Participant has entered. | Participant | None | **200 OK** – list of `{ enrolmentId, eventId, eventName, eventDate, categoryName, status }` · **401 Unauthorized** · **403 Forbidden** |
| DELETE | `/api/enrolments/{id:int}` | Withdraws the Participant from an upcoming event they entered. | Participant (owner) | None | **204 No Content** – withdrawn · **400 Bad Request** – event has already taken place · **401 Unauthorized** · **403 Forbidden** – not their enrolment · **404 Not Found** |
| GET | `/api/events/{eventId:int}/enrolments` | Lists every enrolment for one of the Organiser's events, with participant and category details. | Organiser (owner) | None | **200 OK** – list of `{ enrolmentId, participantName, email, categoryName, raceNumber, status }` · **401 Unauthorized** · **403 Forbidden** – not the owner · **404 Not Found** |

## 7. Results

| HTTP Method | Route | Description | Role Required | Request Body | Expected Response |
|---|---|---|---|---|---|
| POST | `/api/enrolments/{enrolmentId:int}/result` | Captures a Participant's finish time and position after the event; also marks the enrolment Completed. | Organiser (owner of the event) | `{ finishTime: "01:38:42", position }` | **201 Created** – created result · **400 Bad Request** – event has not happened yet, invalid time format, or position ≤ 0 · **401 Unauthorized** · **403 Forbidden** – not the event owner · **404 Not Found** – enrolment not found · **409 Conflict** – result already captured or position already taken in that category |
| PUT | `/api/enrolments/{enrolmentId:int}/result` | Corrects a result that was captured incorrectly. | Organiser (owner of the event) | `{ finishTime, position }` | **200 OK** – updated result · **400 Bad Request** · **401 Unauthorized** · **403 Forbidden** · **404 Not Found** – enrolment or result not found · **409 Conflict** – position already taken |
| GET | `/api/events/{eventId:int}/results` | Returns the results leaderboard for an event, grouped by category and ordered by position. | Any | None | **200 OK** – list of `{ categoryName, position, participantName, finishTime }` · **401 Unauthorized** · **404 Not Found** – event does not exist |
| GET | `/api/results/mine` | Returns the logged-in Participant's personal performance history across all events. | Participant | None | **200 OK** – list of `{ eventName, eventDate, eventType, categoryName, finishTime, position }` · **401 Unauthorized** · **403 Forbidden** |

---

## Coverage check against Part 2 Functional Requirements

| Requirement | Covered by |
|---|---|
| Authentication – register and log in by role | `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/auth/session` |
| User Profile – both roles view and update own profile | `GET /api/users/me`, `PUT /api/users/me`, `PUT /api/users/me/password` |
| Events – Organisers create/update/delete; both roles view; name, description, date, location, distance, type | `GET /api/events`, `GET /api/events/{id}`, `GET /api/events/mine`, `POST`, `PUT`, `DELETE /api/events/{id}`, `GET /api/event-types` |
| Categories – Organisers define age/distance categories; both roles view | `GET` / `POST /api/events/{eventId}/categories`, `PUT` / `DELETE /api/events/{eventId}/categories/{categoryId}` |
| Enrolments – Participant enters via category; link recorded; Organisers view enrolments for their events | `POST /api/events/{eventId}/enrolments`, `GET /api/enrolments/mine`, `DELETE /api/enrolments/{id}`, `GET /api/events/{eventId}/enrolments` |
| Results – Organisers capture time and position; Participants view own results | `POST` / `PUT /api/enrolments/{enrolmentId}/result`, `GET /api/events/{eventId}/results`, `GET /api/results/mine` |

**Total endpoints planned: 26**
