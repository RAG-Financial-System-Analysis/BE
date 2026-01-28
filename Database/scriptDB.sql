
UPDATE "Roles" 
SET "Name" = TRIM("Name"); -- Lệnh này cắt bỏ khoảng trắng đầu đuôi
-- 2. Tạo bảng ROLES (Bảng gốc)
CREATE TABLE "Roles" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "Name" text NOT NULL UNIQUE
);

-- 1. Role Admin (Quản trị hệ thống) - ID toàn số 9
INSERT INTO "Roles" ("Id", "Name")
VALUES ('99999999-9999-9999-9999-999999999999', 'Admin')
ON CONFLICT ("Id") DO NOTHING;

-- 2. Role SourceProvider (Người nhập liệu/Đưa Source) - ID toàn số 7
INSERT INTO "Roles" ("Id", "Name")
VALUES ('77777777-7777-7777-7777-777777777777', 'SourceProvider')
ON CONFLICT ("Id") DO NOTHING;

-- 3. Role Analyst (Người làm báo cáo/Đưa Report) - ID toàn số 6
INSERT INTO "Roles" ("Id", "Name")
VALUES ('66666666-6666-6666-6666-666666666666', 'Analyst')
ON CONFLICT ("Id") DO NOTHING;

-- Role Member cũ (nếu muốn giữ lại)
INSERT INTO "Roles" ("Id", "Name")
VALUES ('88888888-8888-8888-8888-888888888888', 'Member')
ON CONFLICT ("Id") DO NOTHING;

SELECT * FROM "Roles";

-- 3. Tạo bảng USERS (Đã bỏ Password, thêm CognitoSub)
CREATE TABLE "Users" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "RoleId" uuid NOT NULL,
    "CognitoSub" text NOT NULL, -- ID từ AWS
    "Email" text NOT NULL UNIQUE,
    "FullName" text,
    "CreatedAt" timestamp without time zone DEFAULT NOW(),
    CONSTRAINT "FK_Users_Roles" FOREIGN KEY ("RoleId") REFERENCES "Roles" ("Id") ON DELETE CASCADE
);
CREATE UNIQUE INDEX "IX_Users_CognitoSub" ON "Users" ("CognitoSub");

-- 4. Các bảng nghiệp vụ Financial (Dựa trên ERD của Nam)

-- Bảng Công ty
CREATE TABLE "Company" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "Name" text NOT NULL,
    "Ticker" text, -- Mã chứng khoán (e.g., VNM, FPT)
    "Industry" text,
    "Description" text
);

-- Bảng Quy định (Regulation)
CREATE TABLE "Regulation" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "Code" text NOT NULL,
    "Name" text NOT NULL,
    "Description" text
);

-- Bảng Nguồn dữ liệu (Sources)
CREATE TABLE "Sources" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "Name" text NOT NULL,
    "Url" text,
    "Type" text -- e.g., "SEC", "Vietstock"
);

-- Bảng Trung gian: Regulation <-> Sources (Many-to-Many)
CREATE TABLE "Regulation_Sources" (
    "RegulationId" uuid NOT NULL,
    "SourceId" uuid NOT NULL,
    PRIMARY KEY ("RegulationId", "SourceId"),
    CONSTRAINT "FK_RS_Regulation" FOREIGN KEY ("RegulationId") REFERENCES "Regulation" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_RS_Source" FOREIGN KEY ("SourceId") REFERENCES "Sources" ("Id") ON DELETE CASCADE
);

-- Bảng Loại báo cáo (Report Category)
CREATE TABLE "Report_Category" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "Name" text NOT NULL -- e.g., "Balance Sheet", "Income Statement"
);

-- Bảng Báo cáo tài chính (Report_Financial)
CREATE TABLE "Report_Financial" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "CompanyId" uuid NOT NULL,
    "CategoryId" uuid NOT NULL,
    "SourceId" uuid, -- Link đến nguồn lấy báo cáo
    "Year" integer NOT NULL,
    "Period" text, -- Q1, Q2, Annual
    "FileUrl" text, -- Link file PDF/Excel trên S3
    "ContentRaw" text, -- Nội dung thô
    CONSTRAINT "FK_Report_Company" FOREIGN KEY ("CompanyId") REFERENCES "Company" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_Report_Category" FOREIGN KEY ("CategoryId") REFERENCES "Report_Category" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_Report_Source" FOREIGN KEY ("SourceId") REFERENCES "Sources" ("Id") ON DELETE SET NULL
);

-- 5. Các bảng về Chỉ số tài chính (Ratio)

CREATE TABLE "Ratio_Group" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "Name" text NOT NULL -- e.g., "Liquidity", "Profitability"
);

CREATE TABLE "Ratio_Definition" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "GroupId" uuid NOT NULL,
    "Name" text NOT NULL, -- e.g., "Current Ratio"
    "Formula" text,
    "Description" text,
    "ParentId" uuid, -- Self-referencing (Chỉ số cha)
    CONSTRAINT "FK_RatioDef_Group" FOREIGN KEY ("GroupId") REFERENCES "Ratio_Group" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_RatioDef_Parent" FOREIGN KEY ("ParentId") REFERENCES "Ratio_Definition" ("Id")
);

CREATE TABLE "Ratio_Value" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "ReportId" uuid NOT NULL,
    "DefinitionId" uuid NOT NULL,
    "Value" decimal(18, 4), -- Giá trị chỉ số
    CONSTRAINT "FK_RatioVal_Report" FOREIGN KEY ("ReportId") REFERENCES "Report_Financial" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_RatioVal_Def" FOREIGN KEY ("DefinitionId") REFERENCES "Ratio_Definition" ("Id") ON DELETE CASCADE
);

-- 6. Các bảng về Chat & RAG

CREATE TABLE "Chat_Sessions" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "UserId" uuid NOT NULL,
    "Title" text,
    "StartTime" timestamp without time zone DEFAULT NOW(),
    CONSTRAINT "FK_Chat_User" FOREIGN KEY ("UserId") REFERENCES "Users" ("Id") ON DELETE CASCADE
);

CREATE TABLE "Question_Prompt" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "SessionId" uuid NOT NULL,
    "QuestionText" text NOT NULL,
    "ResponseText" text,
    "CreatedAt" timestamp without time zone DEFAULT NOW(),
    CONSTRAINT "FK_Prompt_Session" FOREIGN KEY ("SessionId") REFERENCES "Chat_Sessions" ("Id") ON DELETE CASCADE
);

CREATE TABLE "Analytics_Report" (
    "Id" uuid NOT NULL PRIMARY KEY DEFAULT gen_random_uuid(),
    "ReportFinancialId" uuid, -- Phân tích dựa trên báo cáo nào
    "Title" text,
    "GeneratedContent" text,
    "CreatedAt" timestamp without time zone DEFAULT NOW(),
    CONSTRAINT "FK_Analytics_Report" FOREIGN KEY ("ReportFinancialId") REFERENCES "Report_Financial" ("Id") ON DELETE SET NULL
);

-- Bảng Trung gian: Question <-> Ratio_Value (RAG Context)
CREATE TABLE "Prompt_RatioValues" (
    "PromptId" uuid NOT NULL,
    "RatioValueId" uuid NOT NULL,
    PRIMARY KEY ("PromptId", "RatioValueId"),
    CONSTRAINT "FK_PRV_Prompt" FOREIGN KEY ("PromptId") REFERENCES "Question_Prompt" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_PRV_Ratio" FOREIGN KEY ("RatioValueId") REFERENCES "Ratio_Value" ("Id") ON DELETE CASCADE
);

-- Bảng Trung gian: Question <-> Analytics_Report (RAG Context)
CREATE TABLE "Prompt_Analytics" (
    "PromptId" uuid NOT NULL,
    "AnalyticsId" uuid NOT NULL,
    PRIMARY KEY ("PromptId", "AnalyticsId"),
    CONSTRAINT "FK_PA_Prompt" FOREIGN KEY ("PromptId") REFERENCES "Question_Prompt" ("Id") ON DELETE CASCADE,
    CONSTRAINT "FK_PA_Analytics" FOREIGN KEY ("AnalyticsId") REFERENCES "Analytics_Report" ("Id") ON DELETE CASCADE
);