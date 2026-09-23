/* =====================================================================
   RaceDay - Event Management System
   Part 1: Database Schema and Seed Data (SQL Server / SSMS)
   ---------------------------------------------------------------------
   Run this whole script in SSMS (F5). It drops and recreates the
   RaceDayDB database, so it always runs cleanly on a fresh instance.
   Table order: Roles -> Users -> EventTypes -> Events -> Categories
                -> Enrolments -> Results  (parents before children)
   ===================================================================== */

USE master;
GO

IF DB_ID(N'RaceDayDB') IS NOT NULL
BEGIN
    ALTER DATABASE RaceDayDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE RaceDayDB;
END
GO

CREATE DATABASE RaceDayDB;
GO

USE RaceDayDB;
GO

/* ---------------------------------------------------------------------
   1. Roles - lookup table for the two system roles
   --------------------------------------------------------------------- */
CREATE TABLE Roles (
    RoleId      INT IDENTITY(1,1) NOT NULL,
    RoleName    NVARCHAR(20)      NOT NULL,
    CONSTRAINT PK_Roles PRIMARY KEY (RoleId),
    CONSTRAINT UQ_Roles_RoleName UNIQUE (RoleName)
);
GO

/* ---------------------------------------------------------------------
   2. Users - Organisers and Participants share one table, split by RoleId
   --------------------------------------------------------------------- */
CREATE TABLE Users (
    UserId        INT IDENTITY(1,1) NOT NULL,
    RoleId        INT               NOT NULL,
    FirstName     NVARCHAR(50)      NOT NULL,
    LastName      NVARCHAR(50)      NOT NULL,
    Email         NVARCHAR(100)     NOT NULL,
    PasswordHash  NVARCHAR(255)     NOT NULL,
    PhoneNumber   NVARCHAR(15)      NULL,
    DateOfBirth   DATE              NOT NULL,
    Gender        NVARCHAR(10)      NULL,
    CreatedAt     DATETIME2         NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Users PRIMARY KEY (UserId),
    CONSTRAINT UQ_Users_Email UNIQUE (Email),
    CONSTRAINT FK_Users_Roles FOREIGN KEY (RoleId) REFERENCES Roles(RoleId),
    CONSTRAINT CK_Users_Gender CHECK (Gender IS NULL OR Gender IN (N'Male', N'Female', N'Other'))
);
GO

/* ---------------------------------------------------------------------
   3. EventTypes - lookup table: Run, Walk, Cycle
   --------------------------------------------------------------------- */
CREATE TABLE EventTypes (
    EventTypeId  INT IDENTITY(1,1) NOT NULL,
    TypeName     NVARCHAR(20)      NOT NULL,
    CONSTRAINT PK_EventTypes PRIMARY KEY (EventTypeId),
    CONSTRAINT UQ_EventTypes_TypeName UNIQUE (TypeName)
);
GO

/* ---------------------------------------------------------------------
   4. Events - created and owned by an Organiser
   Latitude/Longitude support the live weather feature (Part 3).
   RouteImageUrl will hold an Azure Blob Storage URL (Part 3).
   --------------------------------------------------------------------- */
CREATE TABLE Events (
    EventId        INT IDENTITY(1,1) NOT NULL,
    OrganiserId    INT               NOT NULL,
    EventTypeId    INT               NOT NULL,
    Name           NVARCHAR(100)     NOT NULL,
    Description    NVARCHAR(1000)    NOT NULL,
    EventDate      DATETIME2         NOT NULL,
    Location       NVARCHAR(150)     NOT NULL,
    Latitude       DECIMAL(9,6)      NULL,
    Longitude      DECIMAL(9,6)      NULL,
    DistanceKm     DECIMAL(6,2)      NOT NULL,
    RouteImageUrl  NVARCHAR(500)     NULL,
    CreatedAt      DATETIME2         NOT NULL CONSTRAINT DF_Events_CreatedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Events PRIMARY KEY (EventId),
    CONSTRAINT FK_Events_Users FOREIGN KEY (OrganiserId) REFERENCES Users(UserId),
    CONSTRAINT FK_Events_EventTypes FOREIGN KEY (EventTypeId) REFERENCES EventTypes(EventTypeId),
    CONSTRAINT CK_Events_DistanceKm CHECK (DistanceKm > 0)
);
GO

/* ---------------------------------------------------------------------
   5. Categories - age or distance categories that belong to one event
   Deleting an event removes its categories (ON DELETE CASCADE).
   UQ_Categories_Id_Event lets Enrolments reference (CategoryId, EventId)
   so an enrolment's category must belong to the same event.
   --------------------------------------------------------------------- */
CREATE TABLE Categories (
    CategoryId       INT IDENTITY(1,1) NOT NULL,
    EventId          INT               NOT NULL,
    Name             NVARCHAR(50)      NOT NULL,
    CategoryType     NVARCHAR(10)      NOT NULL,
    MinAge           INT               NULL,
    MaxAge           INT               NULL,
    DistanceKm       DECIMAL(6,2)      NULL,
    MaxParticipants  INT               NULL,
    CONSTRAINT PK_Categories PRIMARY KEY (CategoryId),
    CONSTRAINT FK_Categories_Events FOREIGN KEY (EventId) REFERENCES Events(EventId) ON DELETE CASCADE,
    CONSTRAINT UQ_Categories_Event_Name UNIQUE (EventId, Name),
    CONSTRAINT UQ_Categories_Id_Event UNIQUE (CategoryId, EventId),
    CONSTRAINT CK_Categories_Type CHECK (CategoryType IN (N'Age', N'Distance')),
    CONSTRAINT CK_Categories_AgeRange CHECK (MinAge IS NULL OR MaxAge IS NULL OR MinAge <= MaxAge),
    CONSTRAINT CK_Categories_MaxParticipants CHECK (MaxParticipants IS NULL OR MaxParticipants > 0)
);
GO

/* ---------------------------------------------------------------------
   6. Enrolments - associative entity resolving the M:N between
   Participants (Users) and Events, recording the chosen Category.
   A participant can enrol in an event only once.
   FKs use NO ACTION to avoid SQL Server "multiple cascade paths";
   the API blocks deleting events/categories that have enrolments (409).
   --------------------------------------------------------------------- */
CREATE TABLE Enrolments (
    EnrolmentId    INT IDENTITY(1,1) NOT NULL,
    ParticipantId  INT               NOT NULL,
    EventId        INT               NOT NULL,
    CategoryId     INT               NOT NULL,
    RaceNumber     INT               NULL,
    Status         NVARCHAR(20)      NOT NULL CONSTRAINT DF_Enrolments_Status DEFAULT N'Registered',
    EnrolledAt     DATETIME2         NOT NULL CONSTRAINT DF_Enrolments_EnrolledAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Enrolments PRIMARY KEY (EnrolmentId),
    CONSTRAINT FK_Enrolments_Users FOREIGN KEY (ParticipantId) REFERENCES Users(UserId),
    CONSTRAINT FK_Enrolments_Events FOREIGN KEY (EventId) REFERENCES Events(EventId),
    CONSTRAINT FK_Enrolments_Categories FOREIGN KEY (CategoryId, EventId)
        REFERENCES Categories(CategoryId, EventId),
    CONSTRAINT UQ_Enrolments_Participant_Event UNIQUE (ParticipantId, EventId),
    CONSTRAINT CK_Enrolments_Status CHECK (Status IN (N'Registered', N'Withdrawn', N'Completed', N'DNF'))
);
GO

/* ---------------------------------------------------------------------
   7. Results - finish time and position for one enrolment (1 : 0..1)
   --------------------------------------------------------------------- */
CREATE TABLE Results (
    ResultId     INT IDENTITY(1,1) NOT NULL,
    EnrolmentId  INT               NOT NULL,
    FinishTime   TIME(0)           NOT NULL,
    Position     INT               NOT NULL,
    RecordedAt   DATETIME2         NOT NULL CONSTRAINT DF_Results_RecordedAt DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Results PRIMARY KEY (ResultId),
    CONSTRAINT FK_Results_Enrolments FOREIGN KEY (EnrolmentId) REFERENCES Enrolments(EnrolmentId) ON DELETE CASCADE,
    CONSTRAINT UQ_Results_Enrolment UNIQUE (EnrolmentId),
    CONSTRAINT CK_Results_Position CHECK (Position > 0)
);
GO

/* =====================================================================
   SEED DATA
   All seeded users share the demo password: RaceDay@2026
   PasswordHash is a real BCrypt hash (cost 11) of that password, so the
   Part 2 API can verify it with BCrypt.Net-Next.
   ===================================================================== */

INSERT INTO Roles (RoleName) VALUES (N'Organiser'), (N'Participant');
-- RoleId 1 = Organiser, 2 = Participant

INSERT INTO EventTypes (TypeName) VALUES (N'Run'), (N'Walk'), (N'Cycle');
-- EventTypeId 1 = Run, 2 = Walk, 3 = Cycle

DECLARE @Hash NVARCHAR(255) = N'$2b$11$zSp.LwK2s0MNN7Ka0YalI.a0mRthZhYpP3HrRL2gtF3GFoY84bD7m';

INSERT INTO Users (RoleId, FirstName, LastName, Email, PasswordHash, PhoneNumber, DateOfBirth, Gender) VALUES
-- Organisers (UserId 1-2)
(1, N'Thandiwe', N'Mokoena',  N'thandiwe.mokoena@jozirunners.co.za', @Hash, N'0821234567', '1985-03-14', N'Female'),
(1, N'Pieter',   N'van Wyk',  N'pieter.vanwyk@capecycling.co.za',    @Hash, N'0839876543', '1979-11-02', N'Male'),
-- Participants (UserId 3-6)
(2, N'Sipho',    N'Ndlovu',   N'sipho.ndlovu@gmail.com',             @Hash, N'0711112222', '1998-07-21', N'Male'),
(2, N'Ayesha',   N'Patel',    N'ayesha.patel@outlook.com',           @Hash, N'0723334444', '2001-01-09', N'Female'),
(2, N'Lerato',   N'Khumalo',  N'lerato.khumalo@yahoo.com',           @Hash, N'0765556666', '1972-05-30', N'Female'),
(2, N'Johan',    N'Botha',    N'johan.botha@gmail.com',              @Hash, NULL,          '2008-09-15', N'Male');

INSERT INTO Events (OrganiserId, EventTypeId, Name, Description, EventDate, Location, Latitude, Longitude, DistanceKm, RouteImageUrl) VALUES
-- EventId 1: past event (has results)
(1, 1, N'Jozi Winter Sunrise 21K',
 N'A fast half marathon through Johannesburg''s northern suburbs, starting at sunrise. Water tables every 3km.',
 '2026-08-16 06:00', N'Emmarentia Dam, Johannesburg', -26.155400, 28.006800, 21.10, NULL),
-- EventId 2: upcoming walk
(1, 2, N'Soweto Heritage Fun Walk',
 N'A relaxed community walk past Soweto''s historic landmarks. Family friendly, all ages welcome.',
 '2026-10-18 07:30', N'Vilakazi Street, Orlando West, Soweto', -26.238400, 27.908700, 8.00, NULL),
-- EventId 3: upcoming cycle
(2, 3, N'Cape Winelands Cycle Classic',
 N'A scenic road cycling race through the Stellenbosch and Franschhoek wine valleys, with two distance options.',
 '2026-11-08 06:30', N'Stellenbosch Town Hall, Stellenbosch', -33.936100, 18.860900, 90.00, NULL);

INSERT INTO Categories (EventId, Name, CategoryType, MinAge, MaxAge, DistanceKm, MaxParticipants) VALUES
-- Event 1: age categories (CategoryId 1-3)
(1, N'Under 20',    N'Age', 16, 19,   NULL, 200),
(1, N'Senior',      N'Age', 20, 39,   NULL, 800),
(1, N'Veteran',     N'Age', 40, NULL, NULL, 500),
-- Event 2: distance categories (CategoryId 4-5)
(2, N'5km',         N'Distance', NULL, NULL, 5.00, NULL),
(2, N'8km',         N'Distance', NULL, NULL, 8.00, NULL),
-- Event 3: distance categories (CategoryId 6-7)
(3, N'45km Fun Ride', N'Distance', 14, NULL, 45.00, 1000),
(3, N'90km Classic',  N'Distance', 18, NULL, 90.00, 1500);

INSERT INTO Enrolments (ParticipantId, EventId, CategoryId, RaceNumber, Status) VALUES
-- Past event 1 (EnrolmentId 1-3)
(3, 1, 2, 1001, N'Completed'),   -- Sipho, Senior
(4, 1, 2, 1002, N'Completed'),   -- Ayesha, Senior
(5, 1, 3, 1003, N'Completed'),   -- Lerato, Veteran
-- Upcoming event 2 (EnrolmentId 4-5)
(5, 2, 4, NULL, N'Registered'),  -- Lerato, 5km
(6, 2, 5, NULL, N'Registered'),  -- Johan, 8km
-- Upcoming event 3 (EnrolmentId 6-7)
(3, 3, 7, NULL, N'Registered'),  -- Sipho, 90km Classic
(4, 3, 6, NULL, N'Registered');  -- Ayesha, 45km Fun Ride

INSERT INTO Results (EnrolmentId, FinishTime, Position) VALUES
(1, '01:38:42', 1),   -- Sipho: 1st Senior
(2, '01:52:15', 2),   -- Ayesha: 2nd Senior
(3, '02:05:09', 1);   -- Lerato: 1st Veteran
GO

/* ---------------------------------------------------------------------
   Verification queries (useful for the video demo)
   --------------------------------------------------------------------- */
SELECT u.UserId, u.FirstName + N' ' + u.LastName AS FullName, r.RoleName, u.Email
FROM Users u JOIN Roles r ON r.RoleId = u.RoleId;

SELECT e.EventId, e.Name, t.TypeName, e.EventDate, e.Location, e.DistanceKm,
       o.FirstName + N' ' + o.LastName AS Organiser
FROM Events e
JOIN EventTypes t ON t.EventTypeId = e.EventTypeId
JOIN Users o ON o.UserId = e.OrganiserId;

SELECT e.Name AS EventName, c.Name AS Category,
       p.FirstName + N' ' + p.LastName AS Participant, en.Status,
       res.FinishTime, res.Position
FROM Enrolments en
JOIN Events e      ON e.EventId = en.EventId
JOIN Categories c  ON c.CategoryId = en.CategoryId
JOIN Users p       ON p.UserId = en.ParticipantId
LEFT JOIN Results res ON res.EnrolmentId = en.EnrolmentId
ORDER BY e.EventId, c.Name, res.Position;
GO
