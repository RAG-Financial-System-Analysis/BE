-- ============================================
-- RAG FINANCIAL ANALYSIS SYSTEM - FINAL DATABASE
-- Version: 1.0
-- Date: 2024-12-01
-- Database: PostgreSQL 14+
-- 
-- CHANGES:
-- - Removed: regulations, sources, regulation_sources (theo yêu cầu giáo viên)
-- - Removed: SourceProvider role
-- - Simplified: Chỉ còn Admin và Analyst roles
-- - Table names: PascalCase (theo ERD conceptual của thầy)
-- ============================================

-- Drop tables if exists (for clean install)
DROP TABLE IF EXISTS Prompt_Analytics CASCADE;
DROP TABLE IF EXISTS Prompt_RatioValues CASCADE;
DROP TABLE IF EXISTS Analytics_Report CASCADE;
DROP TABLE IF EXISTS Question_Prompt CASCADE;
DROP TABLE IF EXISTS Chat_Sessions CASCADE;
DROP TABLE IF EXISTS Analytics_Type CASCADE;
DROP TABLE IF EXISTS Ratio_Value CASCADE;
DROP TABLE IF EXISTS Ratio_Definition CASCADE;
DROP TABLE IF EXISTS Ratio_Group CASCADE;
DROP TABLE IF EXISTS Report_Financial CASCADE;
DROP TABLE IF EXISTS Report_Category CASCADE;
DROP TABLE IF EXISTS Company CASCADE;
DROP TABLE IF EXISTS Audit_Logs CASCADE;
DROP TABLE IF EXISTS Users CASCADE;
DROP TABLE IF EXISTS Roles CASCADE;

-- ============================================
-- 1. AUTHENTICATION & AUTHORIZATION
-- ============================================

-- 1.1. Roles (Vai trò)
CREATE TABLE Roles (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    Name VARCHAR(50) UNIQUE NOT NULL,
    Description TEXT,
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Seed roles
INSERT INTO Roles (Id, Name, Description) VALUES
('99999999-9999-9999-9999-999999999999', 'Admin', 'Quản trị viên hệ thống - Quản lý users, xem tất cả file, bảo mật'),
('66666666-6666-6666-6666-666666666666', 'Analyst', 'Người phân tích - Upload reports, chat với AI, xem analytics');

-- 1.2. Users
CREATE TABLE Users (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    RoleId UUID NOT NULL REFERENCES Roles(Id) ON DELETE RESTRICT,
    CognitoSub TEXT UNIQUE,  -- AWS Cognito ID (optional)
    Email VARCHAR(255) UNIQUE NOT NULL,
    PasswordHash TEXT,  -- Nếu không dùng Cognito
    FullName VARCHAR(255),
    IsActive BOOLEAN DEFAULT true,
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    LastLoginAt TIMESTAMP,
    
    CONSTRAINT chk_auth CHECK (
        (CognitoSub IS NOT NULL) OR (PasswordHash IS NOT NULL)
    )
);

CREATE INDEX idx_users_email ON Users(Email);
CREATE INDEX idx_users_role ON Users(RoleId);
CREATE INDEX idx_users_active ON Users(IsActive);


-- ============================================
-- 2. COMPANY
-- ============================================

-- 2.1. Company (Công ty)
CREATE TABLE Company (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    Ticker VARCHAR(10) UNIQUE NOT NULL,
    Name VARCHAR(255) NOT NULL,
    Industry VARCHAR(100),
    Description TEXT,
    Website VARCHAR(255),
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_company_ticker ON Company(Ticker);
CREATE INDEX idx_company_industry ON Company(Industry);

-- Seed companies
INSERT INTO Company (Ticker, Name, Industry) VALUES
('VNM', 'Vietnam Dairy Products JSC', 'Food & Beverage'),
('FPT', 'FPT Corporation', 'Information Technology'),
('VCB', 'Vietcombank', 'Banking'),
('VIC', 'Vingroup JSC', 'Real Estate'),
('HPG', 'Hoa Phat Group JSC', 'Steel');

-- ============================================
-- 3. FINANCIAL REPORTS
-- ============================================

-- 3.1. Report Category
CREATE TABLE Report_Category (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    Name VARCHAR(100) UNIQUE NOT NULL,
    Description TEXT
);

INSERT INTO Report_Category (Name, Description) VALUES
('Balance Sheet', 'Bảng cân đối kế toán'),
('Income Statement', 'Báo cáo kết quả kinh doanh'),
('Cash Flow Statement', 'Báo cáo lưu chuyển tiền tệ'),
('Notes to Financial Statements', 'Thuyết minh báo cáo tài chính');

-- 3.2. Report Financial (CORE TABLE - CÓ PHÂN QUYỀN!)
CREATE TABLE Report_Financial (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    CompanyId UUID NOT NULL REFERENCES Company(Id) ON DELETE CASCADE,
    CategoryId UUID NOT NULL REFERENCES Report_Category(Id) ON DELETE RESTRICT,
    
    -- Người upload (QUAN TRỌNG cho phân quyền!)
    UploadedBy UUID NOT NULL REFERENCES Users(Id) ON DELETE CASCADE,
    
    -- Thông tin báo cáo
    Year INTEGER NOT NULL,
    Period VARCHAR(10),  -- 'Q1', 'Q2', 'Q3', 'Q4', 'Annual'
    
    -- File storage
    FileUrl TEXT NOT NULL,
    FileName VARCHAR(255),
    FileSizeKb INTEGER,
    
    -- Content (QUAN TRỌNG cho RAG!)
    ContentRaw TEXT,  -- Text đã extract từ PDF
    
    -- Phân quyền (QUAN TRỌNG!)
    Visibility VARCHAR(20) DEFAULT 'private',  -- 'private', 'public', 'team'
    
    -- Metadata
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT chk_visibility CHECK (Visibility IN ('private', 'public', 'team')),
    CONSTRAINT unique_report UNIQUE (CompanyId, CategoryId, Year, Period, UploadedBy)
);

CREATE INDEX idx_report_financial_company ON Report_Financial(CompanyId);
CREATE INDEX idx_report_financial_category ON Report_Financial(CategoryId);
CREATE INDEX idx_report_financial_year ON Report_Financial(Year);
CREATE INDEX idx_report_financial_uploaded_by ON Report_Financial(UploadedBy);
CREATE INDEX idx_report_financial_visibility ON Report_Financial(Visibility);

-- Full-text search index (QUAN TRỌNG cho RAG!)
CREATE INDEX idx_report_financial_content_fts ON Report_Financial 
USING gin(to_tsvector('english', ContentRaw));

-- ============================================
-- 4. FINANCIAL RATIOS (Chỉ số tài chính)
-- ============================================

-- 4.1. Ratio Group
CREATE TABLE Ratio_Group (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    Name VARCHAR(100) UNIQUE NOT NULL,
    Description TEXT
);

INSERT INTO Ratio_Group (Name, Description) VALUES
('Liquidity', 'Chỉ số thanh khoản'),
('Profitability', 'Chỉ số sinh lời'),
('Leverage', 'Chỉ số đòn bẩy tài chính'),
('Efficiency', 'Chỉ số hiệu quả hoạt động'),
('Market', 'Chỉ số thị trường');

-- 4.2. Ratio Definition
CREATE TABLE Ratio_Definition (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    GroupId UUID NOT NULL REFERENCES Ratio_Group(Id) ON DELETE CASCADE,
    ParentId UUID REFERENCES Ratio_Definition(Id) ON DELETE SET NULL,
    
    Code VARCHAR(50) UNIQUE NOT NULL,
    Name VARCHAR(255) NOT NULL,
    Formula TEXT,
    Description TEXT,
    Unit VARCHAR(20),  -- '%', 'times', 'days', etc.
    
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_ratio_definition_group ON Ratio_Definition(GroupId);
CREATE INDEX idx_ratio_definition_code ON Ratio_Definition(Code);

-- Seed common ratios
INSERT INTO Ratio_Definition (GroupId, Code, Name, Formula, Unit) VALUES
((SELECT Id FROM Ratio_Group WHERE Name = 'Profitability'), 'ROE', 'Return on Equity', 'Net Income / Shareholders Equity * 100', '%'),
((SELECT Id FROM Ratio_Group WHERE Name = 'Profitability'), 'ROA', 'Return on Assets', 'Net Income / Total Assets * 100', '%'),
((SELECT Id FROM Ratio_Group WHERE Name = 'Liquidity'), 'CURRENT_RATIO', 'Current Ratio', 'Current Assets / Current Liabilities', 'times'),
((SELECT Id FROM Ratio_Group WHERE Name = 'Leverage'), 'DEBT_TO_EQUITY', 'Debt to Equity', 'Total Debt / Total Equity', 'times'),
((SELECT Id FROM Ratio_Group WHERE Name = 'Profitability'), 'GROSS_MARGIN', 'Gross Profit Margin', 'Gross Profit / Revenue * 100', '%'),
((SELECT Id FROM Ratio_Group WHERE Name = 'Profitability'), 'NET_MARGIN', 'Net Profit Margin', 'Net Income / Revenue * 100', '%');

-- 4.3. Ratio Value
CREATE TABLE Ratio_Value (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ReportId UUID NOT NULL REFERENCES Report_Financial(Id) ON DELETE CASCADE,
    DefinitionId UUID NOT NULL REFERENCES Ratio_Definition(Id) ON DELETE CASCADE,
    
    Value DECIMAL(18, 4),
    
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT unique_ratio_value UNIQUE (ReportId, DefinitionId)
);

CREATE INDEX idx_ratio_value_report ON Ratio_Value(ReportId);
CREATE INDEX idx_ratio_value_definition ON Ratio_Value(DefinitionId);


-- ============================================
-- 5. RAG CHATBOT (CORE FEATURE!)
-- ============================================

-- 5.1. Analytics Type (User chọn loại phân tích)
CREATE TABLE Analytics_Type (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    Code VARCHAR(50) UNIQUE NOT NULL,
    Name VARCHAR(100) NOT NULL,
    Description TEXT,
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO Analytics_Type (Code, Name, Description) VALUES
('RISK', 'Risk Analysis', 'Phân tích rủi ro tài chính'),
('TREND', 'Trend Analysis', 'Phân tích xu hướng phát triển'),
('COMPARISON', 'Comparative Analysis', 'So sánh giữa các công ty'),
('OPPORTUNITY', 'Opportunity Analysis', 'Phân tích cơ hội đầu tư'),
('EXECUTIVE', 'Executive Summary', 'Tóm tắt tổng quan');

CREATE INDEX idx_analytics_type_code ON Analytics_Type(Code);

-- 5.2. Chat Sessions (Liên kết với Analytics_Type)
CREATE TABLE Chat_Sessions (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    UserId UUID NOT NULL REFERENCES Users(Id) ON DELETE CASCADE,
    AnalyticsTypeId UUID REFERENCES Analytics_Type(Id) ON DELETE SET NULL,
    
    Title VARCHAR(255),
    StartTime TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    LastMessageAt TIMESTAMP,
    
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_chat_sessions_user ON Chat_Sessions(UserId);
CREATE INDEX idx_chat_sessions_analytics_type ON Chat_Sessions(AnalyticsTypeId);
CREATE INDEX idx_chat_sessions_created ON Chat_Sessions(CreatedAt DESC);

-- 5.3. Question Prompt (Chat Messages)
CREATE TABLE Question_Prompt (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    SessionId UUID NOT NULL REFERENCES Chat_Sessions(Id) ON DELETE CASCADE,
    
    QuestionText TEXT NOT NULL,
    ResponseText TEXT,
    
    -- RAG metadata
    RetrievalCount INTEGER DEFAULT 0,  -- Số lượng documents retrieved
    GenerationModel VARCHAR(50),  -- 'custom', 'gpt-4', etc.
    
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_question_prompt_session ON Question_Prompt(SessionId);
CREATE INDEX idx_question_prompt_created ON Question_Prompt(CreatedAt DESC);

-- 5.4. Prompt_RatioValues (RAG Context - Citations)
CREATE TABLE Prompt_RatioValues (
    PromptId UUID NOT NULL REFERENCES Question_Prompt(Id) ON DELETE CASCADE,
    RatioValueId UUID NOT NULL REFERENCES Ratio_Value(Id) ON DELETE CASCADE,
    
    RelevanceScore DECIMAL(5, 4),  -- 0.0000 to 1.0000
    
    PRIMARY KEY (PromptId, RatioValueId)
);

CREATE INDEX idx_prompt_ratio_values_prompt ON Prompt_RatioValues(PromptId);
CREATE INDEX idx_prompt_ratio_values_ratio ON Prompt_RatioValues(RatioValueId);

-- ============================================
-- 6. ANALYTICS (File phân tích AI gen ra)
-- ============================================

-- 6.1. Analytics Report (Liên kết với Chat_Session)
CREATE TABLE Analytics_Report (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    SessionId UUID REFERENCES Chat_Sessions(Id) ON DELETE CASCADE,  -- Liên kết với session
    ReportFinancialId UUID REFERENCES Report_Financial(Id) ON DELETE SET NULL,
    
    Title VARCHAR(255),
    GeneratedContent TEXT,  -- Nội dung phân tích (JSON/Text)
    FileUrl TEXT,  -- URL file phân tích (PDF, Excel, biểu đồ)
    
    -- Metadata
    GenerationType VARCHAR(50),  -- 'auto', 'manual', 'scheduled'
    GeneratedBy UUID REFERENCES Users(Id) ON DELETE SET NULL,
    
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_analytics_report_session ON Analytics_Report(SessionId);
CREATE INDEX idx_analytics_report_financial ON Analytics_Report(ReportFinancialId);
CREATE INDEX idx_analytics_report_created ON Analytics_Report(CreatedAt DESC);

-- 6.2. Prompt_Analytics (RAG Context - Citations)
CREATE TABLE Prompt_Analytics (
    PromptId UUID NOT NULL REFERENCES Question_Prompt(Id) ON DELETE CASCADE,
    AnalyticsId UUID NOT NULL REFERENCES Analytics_Report(Id) ON DELETE CASCADE,
    
    RelevanceScore DECIMAL(5, 4),
    
    PRIMARY KEY (PromptId, AnalyticsId)
);

CREATE INDEX idx_prompt_analytics_prompt ON Prompt_Analytics(PromptId);
CREATE INDEX idx_prompt_analytics_analytics ON Prompt_Analytics(AnalyticsId);

-- ============================================
-- 7. AUDIT & LOGGING (Cho Admin)
-- ============================================

CREATE TABLE Audit_Logs (
    Id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    UserId UUID REFERENCES Users(Id) ON DELETE SET NULL,
    
    Action VARCHAR(100) NOT NULL,  -- 'upload', 'delete', 'view', 'publish', etc.
    ResourceType VARCHAR(50),  -- 'report', 'user', 'chat', etc.
    ResourceId UUID,
    
    Details TEXT,
    IpAddress VARCHAR(50),
    UserAgent TEXT,
    
    CreatedAt TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_logs_user ON Audit_Logs(UserId);
CREATE INDEX idx_audit_logs_action ON Audit_Logs(Action);
CREATE INDEX idx_audit_logs_resource ON Audit_Logs(ResourceType, ResourceId);
CREATE INDEX idx_audit_logs_created ON Audit_Logs(CreatedAt DESC);

-- ============================================
-- 8. VIEWS (Helper views)
-- ============================================

-- View: Reports với thông tin đầy đủ
CREATE OR REPLACE VIEW V_Reports_Full AS
SELECT 
    r.Id,
    r.Year,
    r.Period,
    r.FileUrl,
    r.FileName,
    r.Visibility,
    r.CreatedAt,
    c.Ticker,
    c.Name as CompanyName,
    cat.Name as CategoryName,
    u.FullName as UploadedByName,
    u.Id as UploadedById,
    (SELECT COUNT(*) FROM Ratio_Value rv WHERE rv.ReportId = r.Id) as RatioCount
FROM Report_Financial r
JOIN Company c ON r.CompanyId = c.Id
JOIN Report_Category cat ON r.CategoryId = cat.Id
JOIN Users u ON r.UploadedBy = u.Id;

-- View: Chat history với citations và analytics type
CREATE OR REPLACE VIEW V_Chat_History AS
SELECT 
    qp.Id as MessageId,
    qp.SessionId,
    qp.QuestionText,
    qp.ResponseText,
    qp.CreatedAt,
    cs.UserId,
    cs.AnalyticsTypeId,
    u.FullName as UserName,
    at.Name as AnalyticsTypeName,
    at.Code as AnalyticsTypeCode,
    (SELECT COUNT(*) FROM Prompt_RatioValues prv WHERE prv.PromptId = qp.Id) as CitationCount,
    (SELECT COUNT(*) FROM Analytics_Report ar WHERE ar.SessionId = cs.Id) as AnalyticsReportCount
FROM Question_Prompt qp
JOIN Chat_Sessions cs ON qp.SessionId = cs.Id
JOIN Users u ON cs.UserId = u.Id
LEFT JOIN Analytics_Type at ON cs.AnalyticsTypeId = at.Id
ORDER BY qp.CreatedAt DESC;

-- View: Company statistics
CREATE OR REPLACE VIEW V_Company_Stats AS
SELECT 
    c.Id,
    c.Ticker,
    c.Name,
    c.Industry,
    COUNT(DISTINCT r.Id) as TotalReports,
    COUNT(DISTINCT CASE WHEN r.Visibility = 'public' THEN r.Id END) as PublicReports,
    MIN(r.Year) as EarliestYear,
    MAX(r.Year) as LatestYear,
    COUNT(DISTINCT rv.Id) as TotalRatios
FROM Company c
LEFT JOIN Report_Financial r ON c.Id = r.CompanyId
LEFT JOIN Ratio_Value rv ON r.Id = rv.ReportId
GROUP BY c.Id, c.Ticker, c.Name, c.Industry;

-- ============================================
-- 9. FUNCTIONS
-- ============================================

-- Function: RAG Search (Full-text search với phân quyền)
CREATE OR REPLACE FUNCTION RAG_Search(
    search_query TEXT,
    current_user_id UUID,
    current_user_role TEXT,
    limit_count INTEGER DEFAULT 10
)
RETURNS TABLE (
    ReportId UUID,
    CompanyTicker VARCHAR(10),
    CompanyName VARCHAR(255),
    CategoryName VARCHAR(100),
    Year INTEGER,
    Period VARCHAR(10),
    Relevance REAL,
    Snippet TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.Id,
        c.Ticker,
        c.Name,
        cat.Name,
        r.Year,
        r.Period,
        ts_rank(to_tsvector('english', r.ContentRaw), plainto_tsquery('english', search_query)) as relevance,
        substring(r.ContentRaw, 1, 500) as snippet
    FROM Report_Financial r
    JOIN Company c ON r.CompanyId = c.Id
    JOIN Report_Category cat ON r.CategoryId = cat.Id
    WHERE 
        to_tsvector('english', r.ContentRaw) @@ plainto_tsquery('english', search_query)
        AND (
            -- Admin xem tất cả
            current_user_role = 'Admin'
            OR
            -- Owner xem file của mình
            r.UploadedBy = current_user_id
            OR
            -- Public files
            r.Visibility = 'public'
        )
    ORDER BY relevance DESC
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- Function: Check user permission on report
CREATE OR REPLACE FUNCTION Can_Access_Report(
    report_id_param UUID,
    user_id_param UUID,
    user_role_param TEXT
)
RETURNS BOOLEAN AS $$
DECLARE
    report_visibility TEXT;
    report_owner UUID;
BEGIN
    SELECT Visibility, UploadedBy 
    INTO report_visibility, report_owner
    FROM Report_Financial
    WHERE Id = report_id_param;
    
    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;
    
    -- Admin có quyền xem tất cả
    IF user_role_param = 'Admin' THEN
        RETURN TRUE;
    END IF;
    
    -- Owner có quyền xem file của mình
    IF report_owner = user_id_param THEN
        RETURN TRUE;
    END IF;
    
    -- Public files
    IF report_visibility = 'public' THEN
        RETURN TRUE;
    END IF;
    
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Function: Update LastMessageAt in Chat_Sessions
CREATE OR REPLACE FUNCTION Update_Chat_Session_Timestamp()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE Chat_Sessions
    SET LastMessageAt = NEW.CreatedAt
    WHERE Id = NEW.SessionId;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_chat_timestamp
AFTER INSERT ON Question_Prompt
FOR EACH ROW
EXECUTE FUNCTION Update_Chat_Session_Timestamp();

-- ============================================
-- 10. SAMPLE DATA (Optional - for testing)
-- ============================================

-- Sample user (Analyst)
INSERT INTO Users (RoleId, Email, PasswordHash, FullName) VALUES
((SELECT Id FROM Roles WHERE Name = 'Analyst'), 
 'analyst@example.com', 
 '$2a$11$hashed_password_here',  -- Replace with actual hash
 'Nguyen Van A');

-- Sample admin
INSERT INTO Users (RoleId, Email, PasswordHash, FullName) VALUES
((SELECT Id FROM Roles WHERE Name = 'Admin'), 
 'admin@example.com', 
 '$2a$11$hashed_password_here',  -- Replace with actual hash
 'Admin User');

-- ============================================
-- 11. PERMISSIONS & GRANTS
-- ============================================

-- Grant permissions (uncomment and adjust for your user)
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO your_app_user;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO your_app_user;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO your_app_user;

-- ============================================
-- DONE!
-- ============================================

-- Verify tables
SELECT 
    schemaname,
    tablename,
    tableowner
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- Verify indexes
SELECT 
    schemaname,
    tablename,
    indexname
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
