using System;
using System.Collections.Generic;
using Microsoft.EntityFrameworkCore;
using RAG.Domain;
namespace RAG.Infrastructure.Database;

public partial class ApplicationDbContext : DbContext
{
    public ApplicationDbContext()
    {
    }

    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public virtual DbSet<AnalyticsReport> AnalyticsReports { get; set; }

    public virtual DbSet<AnalyticsType> AnalyticsTypes { get; set; }

    public virtual DbSet<AuditLog> AuditLogs { get; set; }

    public virtual DbSet<ChatSession> ChatSessions { get; set; }

    public virtual DbSet<Company> Companies { get; set; }

    public virtual DbSet<PromptAnalytic> PromptAnalytics { get; set; }

    public virtual DbSet<PromptRatiovalue> PromptRatiovalues { get; set; }

    public virtual DbSet<QuestionPrompt> QuestionPrompts { get; set; }

    public virtual DbSet<RatioDefinition> RatioDefinitions { get; set; }

    public virtual DbSet<RatioGroup> RatioGroups { get; set; }

    public virtual DbSet<RatioValue> RatioValues { get; set; }

    public virtual DbSet<ReportCategory> ReportCategories { get; set; }

    public virtual DbSet<ReportFinancial> ReportFinancials { get; set; }

    public virtual DbSet<Role> Roles { get; set; }

    public virtual DbSet<User> Users { get; set; }

    public virtual DbSet<VChatHistory> VChatHistories { get; set; }

    public virtual DbSet<VCompanyStat> VCompanyStats { get; set; }

    public virtual DbSet<VReportsFull> VReportsFulls { get; set; }

    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
#warning To protect potentially sensitive information in your connection string, you should move it out of source code. You can avoid scaffolding the connection string by using the Name= syntax to read it from configuration - see https://go.microsoft.com/fwlink/?linkid=2131148. For more guidance on storing connection strings, see https://go.microsoft.com/fwlink/?LinkId=723263.
        => optionsBuilder.UseNpgsql("Host=localhost;Database=RAG-System;Username=postgres;Password=123456", x => x.UseVector());

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<AnalyticsReport>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("analytics_report_pkey");

            entity.ToTable("analytics_report");

            entity.HasIndex(e => e.Createdat, "idx_analytics_report_created").IsDescending();

            entity.HasIndex(e => e.Reportfinancialid, "idx_analytics_report_financial");

            entity.HasIndex(e => e.Sessionid, "idx_analytics_report_session");

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Createdat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Fileurl).HasColumnName("fileurl");
            entity.Property(e => e.Generatedby).HasColumnName("generatedby");
            entity.Property(e => e.Generatedcontent).HasColumnName("generatedcontent");
            entity.Property(e => e.Generationtype)
                .HasMaxLength(50)
                .HasColumnName("generationtype");
            entity.Property(e => e.Reportfinancialid).HasColumnName("reportfinancialid");
            entity.Property(e => e.Sessionid).HasColumnName("sessionid");
            entity.Property(e => e.Title)
                .HasMaxLength(255)
                .HasColumnName("title");

            entity.HasOne(d => d.GeneratedbyNavigation).WithMany(p => p.AnalyticsReports)
                .HasForeignKey(d => d.Generatedby)
                .OnDelete(DeleteBehavior.SetNull)
                .HasConstraintName("analytics_report_generatedby_fkey");

            entity.HasOne(d => d.Reportfinancial).WithMany(p => p.AnalyticsReports)
                .HasForeignKey(d => d.Reportfinancialid)
                .OnDelete(DeleteBehavior.SetNull)
                .HasConstraintName("analytics_report_reportfinancialid_fkey");

            entity.HasOne(d => d.Session).WithMany(p => p.AnalyticsReports)
                .HasForeignKey(d => d.Sessionid)
                .OnDelete(DeleteBehavior.Cascade)
                .HasConstraintName("analytics_report_sessionid_fkey");
        });

        modelBuilder.Entity<AnalyticsType>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("analytics_type_pkey");

            entity.ToTable("analytics_type");

            entity.HasIndex(e => e.Code, "analytics_type_code_key").IsUnique();

            entity.HasIndex(e => e.Code, "idx_analytics_type_code");

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Code)
                .HasMaxLength(50)
                .HasColumnName("code");
            entity.Property(e => e.Createdat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Description).HasColumnName("description");
            entity.Property(e => e.Name)
                .HasMaxLength(100)
                .HasColumnName("name");
        });

        modelBuilder.Entity<AuditLog>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("audit_logs_pkey");

            entity.ToTable("audit_logs");

            entity.HasIndex(e => e.Action, "idx_audit_logs_action");

            entity.HasIndex(e => e.Createdat, "idx_audit_logs_created").IsDescending();

            entity.HasIndex(e => new { e.Resourcetype, e.Resourceid }, "idx_audit_logs_resource");

            entity.HasIndex(e => e.Userid, "idx_audit_logs_user");

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Action)
                .HasMaxLength(100)
                .HasColumnName("action");
            entity.Property(e => e.Createdat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Details).HasColumnName("details");
            entity.Property(e => e.Ipaddress)
                .HasMaxLength(50)
                .HasColumnName("ipaddress");
            entity.Property(e => e.Resourceid).HasColumnName("resourceid");
            entity.Property(e => e.Resourcetype)
                .HasMaxLength(50)
                .HasColumnName("resourcetype");
            entity.Property(e => e.Useragent).HasColumnName("useragent");
            entity.Property(e => e.Userid).HasColumnName("userid");

            entity.HasOne(d => d.User).WithMany(p => p.AuditLogs)
                .HasForeignKey(d => d.Userid)
                .OnDelete(DeleteBehavior.SetNull)
                .HasConstraintName("audit_logs_userid_fkey");
        });

        modelBuilder.Entity<ChatSession>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("chat_sessions_pkey");

            entity.ToTable("chat_sessions");

            entity.HasIndex(e => e.Analyticstypeid, "idx_chat_sessions_analytics_type");

            entity.HasIndex(e => e.Createdat, "idx_chat_sessions_created").IsDescending();

            entity.HasIndex(e => e.Userid, "idx_chat_sessions_user");

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Analyticstypeid).HasColumnName("analyticstypeid");
            entity.Property(e => e.Createdat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Lastmessageat)
                .HasColumnType("timestamp without time zone")
                .HasColumnName("lastmessageat");
            entity.Property(e => e.Starttime)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("starttime");
            entity.Property(e => e.Title)
                .HasMaxLength(255)
                .HasColumnName("title");
            entity.Property(e => e.Userid).HasColumnName("userid");

            entity.HasOne(d => d.Analyticstype).WithMany(p => p.ChatSessions)
                .HasForeignKey(d => d.Analyticstypeid)
                .OnDelete(DeleteBehavior.SetNull)
                .HasConstraintName("chat_sessions_analyticstypeid_fkey");

            entity.HasOne(d => d.User).WithMany(p => p.ChatSessions)
                .HasForeignKey(d => d.Userid)
                .HasConstraintName("chat_sessions_userid_fkey");
        });

        modelBuilder.Entity<Company>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("company_pkey");

            entity.ToTable("company");

            entity.HasIndex(e => e.Ticker, "company_ticker_key").IsUnique();

            entity.HasIndex(e => e.Industry, "idx_company_industry");

            entity.HasIndex(e => e.Ticker, "idx_company_ticker");

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Createdat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Description).HasColumnName("description");
            entity.Property(e => e.Industry)
                .HasMaxLength(100)
                .HasColumnName("industry");
            entity.Property(e => e.Name)
                .HasMaxLength(255)
                .HasColumnName("name");
            entity.Property(e => e.Ticker)
                .HasMaxLength(10)
                .HasColumnName("ticker");
            entity.Property(e => e.Updatedat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("updatedat");
            entity.Property(e => e.Website)
                .HasMaxLength(255)
                .HasColumnName("website");
        });

        modelBuilder.Entity<PromptAnalytic>(entity =>
        {
            entity.HasKey(e => new { e.Promptid, e.Analyticsid }).HasName("prompt_analytics_pkey");

            entity.ToTable("prompt_analytics");

            entity.HasIndex(e => e.Analyticsid, "idx_prompt_analytics_analytics");

            entity.HasIndex(e => e.Promptid, "idx_prompt_analytics_prompt");

            entity.Property(e => e.Promptid).HasColumnName("promptid");
            entity.Property(e => e.Analyticsid).HasColumnName("analyticsid");
            entity.Property(e => e.Relevancescore)
                .HasPrecision(5, 4)
                .HasColumnName("relevancescore");

            entity.HasOne(d => d.Analytics).WithMany(p => p.PromptAnalytics)
                .HasForeignKey(d => d.Analyticsid)
                .HasConstraintName("prompt_analytics_analyticsid_fkey");

            entity.HasOne(d => d.Prompt).WithMany(p => p.PromptAnalytics)
                .HasForeignKey(d => d.Promptid)
                .HasConstraintName("prompt_analytics_promptid_fkey");
        });

        modelBuilder.Entity<PromptRatiovalue>(entity =>
        {
            entity.HasKey(e => new { e.Promptid, e.Ratiovalueid }).HasName("prompt_ratiovalues_pkey");

            entity.ToTable("prompt_ratiovalues");

            entity.HasIndex(e => e.Promptid, "idx_prompt_ratio_values_prompt");

            entity.HasIndex(e => e.Ratiovalueid, "idx_prompt_ratio_values_ratio");

            entity.Property(e => e.Promptid).HasColumnName("promptid");
            entity.Property(e => e.Ratiovalueid).HasColumnName("ratiovalueid");
            entity.Property(e => e.Relevancescore)
                .HasPrecision(5, 4)
                .HasColumnName("relevancescore");

            entity.HasOne(d => d.Prompt).WithMany(p => p.PromptRatiovalues)
                .HasForeignKey(d => d.Promptid)
                .HasConstraintName("prompt_ratiovalues_promptid_fkey");

            entity.HasOne(d => d.Ratiovalue).WithMany(p => p.PromptRatiovalues)
                .HasForeignKey(d => d.Ratiovalueid)
                .HasConstraintName("prompt_ratiovalues_ratiovalueid_fkey");
        });

        modelBuilder.Entity<QuestionPrompt>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("question_prompt_pkey");

            entity.ToTable("question_prompt");

            entity.HasIndex(e => e.Createdat, "idx_question_prompt_created").IsDescending();

            entity.HasIndex(e => e.Sessionid, "idx_question_prompt_session");

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Createdat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Generationmodel)
                .HasMaxLength(50)
                .HasColumnName("generationmodel");
            entity.Property(e => e.Questiontext).HasColumnName("questiontext");
            entity.Property(e => e.Responsetext).HasColumnName("responsetext");
            entity.Property(e => e.Retrievalcount)
                .HasDefaultValue(0)
                .HasColumnName("retrievalcount");
            entity.Property(e => e.Sessionid).HasColumnName("sessionid");

            entity.HasOne(d => d.Session).WithMany(p => p.QuestionPrompts)
                .HasForeignKey(d => d.Sessionid)
                .HasConstraintName("question_prompt_sessionid_fkey");
        });

        modelBuilder.Entity<RatioDefinition>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("ratio_definition_pkey");

            entity.ToTable("ratio_definition");

            entity.HasIndex(e => e.Code, "idx_ratio_definition_code");

            entity.HasIndex(e => e.Groupid, "idx_ratio_definition_group");

            entity.HasIndex(e => e.Code, "ratio_definition_code_key").IsUnique();

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Code)
                .HasMaxLength(50)
                .HasColumnName("code");
            entity.Property(e => e.Createdat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Description).HasColumnName("description");
            entity.Property(e => e.Formula).HasColumnName("formula");
            entity.Property(e => e.Groupid).HasColumnName("groupid");
            entity.Property(e => e.Name)
                .HasMaxLength(255)
                .HasColumnName("name");
            entity.Property(e => e.Parentid).HasColumnName("parentid");
            entity.Property(e => e.Unit)
                .HasMaxLength(20)
                .HasColumnName("unit");

            entity.HasOne(d => d.Group).WithMany(p => p.RatioDefinitions)
                .HasForeignKey(d => d.Groupid)
                .HasConstraintName("ratio_definition_groupid_fkey");

            entity.HasOne(d => d.Parent).WithMany(p => p.InverseParent)
                .HasForeignKey(d => d.Parentid)
                .OnDelete(DeleteBehavior.SetNull)
                .HasConstraintName("ratio_definition_parentid_fkey");
        });

        modelBuilder.Entity<RatioGroup>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("ratio_group_pkey");

            entity.ToTable("ratio_group");

            entity.HasIndex(e => e.Name, "ratio_group_name_key").IsUnique();

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Description).HasColumnName("description");
            entity.Property(e => e.Name)
                .HasMaxLength(100)
                .HasColumnName("name");
        });

        modelBuilder.Entity<RatioValue>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("ratio_value_pkey");

            entity.ToTable("ratio_value");

            entity.HasIndex(e => e.Definitionid, "idx_ratio_value_definition");

            entity.HasIndex(e => e.Reportid, "idx_ratio_value_report");

            entity.HasIndex(e => new { e.Reportid, e.Definitionid }, "unique_ratio_value").IsUnique();

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Createdat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Definitionid).HasColumnName("definitionid");
            entity.Property(e => e.Reportid).HasColumnName("reportid");
            entity.Property(e => e.Value)
                .HasPrecision(18, 4)
                .HasColumnName("value");

            entity.HasOne(d => d.Definition).WithMany(p => p.RatioValues)
                .HasForeignKey(d => d.Definitionid)
                .HasConstraintName("ratio_value_definitionid_fkey");

            entity.HasOne(d => d.Report).WithMany(p => p.RatioValues)
                .HasForeignKey(d => d.Reportid)
                .HasConstraintName("ratio_value_reportid_fkey");
        });

        modelBuilder.Entity<ReportCategory>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("report_category_pkey");

            entity.ToTable("report_category");

            entity.HasIndex(e => e.Name, "report_category_name_key").IsUnique();

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Description).HasColumnName("description");
            entity.Property(e => e.Name)
                .HasMaxLength(100)
                .HasColumnName("name");
        });

        modelBuilder.Entity<ReportFinancial>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("report_financial_pkey");

            entity.ToTable("report_financial");

            entity.HasIndex(e => e.Categoryid, "idx_report_financial_category");

            entity.HasIndex(e => e.Companyid, "idx_report_financial_company");

            entity.HasIndex(e => e.Uploadedby, "idx_report_financial_uploaded_by");

            entity.HasIndex(e => e.Visibility, "idx_report_financial_visibility");

            entity.HasIndex(e => e.Year, "idx_report_financial_year");

            entity.HasIndex(e => new { e.Companyid, e.Categoryid, e.Year, e.Period, e.Uploadedby }, "unique_report").IsUnique();

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Categoryid).HasColumnName("categoryid");
            entity.Property(e => e.Companyid).HasColumnName("companyid");
            entity.Property(e => e.Contentraw).HasColumnName("contentraw");
            entity.Property(e => e.Createdat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Filename)
                .HasMaxLength(255)
                .HasColumnName("filename");
            entity.Property(e => e.Filesizekb).HasColumnName("filesizekb");
            entity.Property(e => e.Fileurl).HasColumnName("fileurl");
            entity.Property(e => e.Period)
                .HasMaxLength(10)
                .HasColumnName("period");
            entity.Property(e => e.Updatedat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("updatedat");
            entity.Property(e => e.Uploadedby).HasColumnName("uploadedby");
            entity.Property(e => e.Visibility)
                .HasMaxLength(20)
                .HasDefaultValueSql("'private'::character varying")
                .HasColumnName("visibility");
            entity.Property(e => e.Year).HasColumnName("year");

            entity.HasOne(d => d.Category).WithMany(p => p.ReportFinancials)
                .HasForeignKey(d => d.Categoryid)
                .OnDelete(DeleteBehavior.Restrict)
                .HasConstraintName("report_financial_categoryid_fkey");

            entity.HasOne(d => d.Company).WithMany(p => p.ReportFinancials)
                .HasForeignKey(d => d.Companyid)
                .HasConstraintName("report_financial_companyid_fkey");

            entity.HasOne(d => d.UploadedbyNavigation).WithMany(p => p.ReportFinancials)
                .HasForeignKey(d => d.Uploadedby)
                .HasConstraintName("report_financial_uploadedby_fkey");
        });

        modelBuilder.Entity<Role>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("roles_pkey");

            entity.ToTable("roles");

            entity.HasIndex(e => e.Name, "roles_name_key").IsUnique();

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Createdat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Description).HasColumnName("description");
            entity.Property(e => e.Name)
                .HasMaxLength(50)
                .HasColumnName("name");
        });

        modelBuilder.Entity<User>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("users_pkey");

            entity.ToTable("users");

            entity.HasIndex(e => e.Isactive, "idx_users_active");

            entity.HasIndex(e => e.Email, "idx_users_email");

            entity.HasIndex(e => e.Roleid, "idx_users_role");

            entity.HasIndex(e => e.Cognitosub, "users_cognitosub_key").IsUnique();

            entity.HasIndex(e => e.Email, "users_email_key").IsUnique();

            entity.Property(e => e.Id)
                .HasDefaultValueSql("gen_random_uuid()")
                .HasColumnName("id");
            entity.Property(e => e.Cognitosub).HasColumnName("cognitosub");
            entity.Property(e => e.Createdat)
                .HasDefaultValueSql("CURRENT_TIMESTAMP")
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Email)
                .HasMaxLength(255)
                .HasColumnName("email");
            entity.Property(e => e.Fullname)
                .HasMaxLength(255)
                .HasColumnName("fullname");
            entity.Property(e => e.Isactive)
                .HasDefaultValue(true)
                .HasColumnName("isactive");
            entity.Property(e => e.Lastloginat)
                .HasColumnType("timestamp without time zone")
                .HasColumnName("lastloginat");
            entity.Property(e => e.Passwordhash).HasColumnName("passwordhash");
            entity.Property(e => e.Roleid).HasColumnName("roleid");

            entity.HasOne(d => d.Role).WithMany(p => p.Users)
                .HasForeignKey(d => d.Roleid)
                .OnDelete(DeleteBehavior.Restrict)
                .HasConstraintName("users_roleid_fkey");
        });

        modelBuilder.Entity<VChatHistory>(entity =>
        {
            entity
                .HasNoKey()
                .ToView("v_chat_history");

            entity.Property(e => e.Analyticsreportcount).HasColumnName("analyticsreportcount");
            entity.Property(e => e.Analyticstypecode)
                .HasMaxLength(50)
                .HasColumnName("analyticstypecode");
            entity.Property(e => e.Analyticstypeid).HasColumnName("analyticstypeid");
            entity.Property(e => e.Analyticstypename)
                .HasMaxLength(100)
                .HasColumnName("analyticstypename");
            entity.Property(e => e.Citationcount).HasColumnName("citationcount");
            entity.Property(e => e.Createdat)
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Messageid).HasColumnName("messageid");
            entity.Property(e => e.Questiontext).HasColumnName("questiontext");
            entity.Property(e => e.Responsetext).HasColumnName("responsetext");
            entity.Property(e => e.Sessionid).HasColumnName("sessionid");
            entity.Property(e => e.Userid).HasColumnName("userid");
            entity.Property(e => e.Username)
                .HasMaxLength(255)
                .HasColumnName("username");
        });

        modelBuilder.Entity<VCompanyStat>(entity =>
        {
            entity
                .HasNoKey()
                .ToView("v_company_stats");

            entity.Property(e => e.Earliestyear).HasColumnName("earliestyear");
            entity.Property(e => e.Id).HasColumnName("id");
            entity.Property(e => e.Industry)
                .HasMaxLength(100)
                .HasColumnName("industry");
            entity.Property(e => e.Latestyear).HasColumnName("latestyear");
            entity.Property(e => e.Name)
                .HasMaxLength(255)
                .HasColumnName("name");
            entity.Property(e => e.Publicreports).HasColumnName("publicreports");
            entity.Property(e => e.Ticker)
                .HasMaxLength(10)
                .HasColumnName("ticker");
            entity.Property(e => e.Totalratios).HasColumnName("totalratios");
            entity.Property(e => e.Totalreports).HasColumnName("totalreports");
        });

        modelBuilder.Entity<VReportsFull>(entity =>
        {
            entity
                .HasNoKey()
                .ToView("v_reports_full");

            entity.Property(e => e.Categoryname)
                .HasMaxLength(100)
                .HasColumnName("categoryname");
            entity.Property(e => e.Companyname)
                .HasMaxLength(255)
                .HasColumnName("companyname");
            entity.Property(e => e.Createdat)
                .HasColumnType("timestamp without time zone")
                .HasColumnName("createdat");
            entity.Property(e => e.Filename)
                .HasMaxLength(255)
                .HasColumnName("filename");
            entity.Property(e => e.Fileurl).HasColumnName("fileurl");
            entity.Property(e => e.Id).HasColumnName("id");
            entity.Property(e => e.Period)
                .HasMaxLength(10)
                .HasColumnName("period");
            entity.Property(e => e.Ratiocount).HasColumnName("ratiocount");
            entity.Property(e => e.Ticker)
                .HasMaxLength(10)
                .HasColumnName("ticker");
            entity.Property(e => e.Uploadedbyid).HasColumnName("uploadedbyid");
            entity.Property(e => e.Uploadedbyname)
                .HasMaxLength(255)
                .HasColumnName("uploadedbyname");
            entity.Property(e => e.Visibility)
                .HasMaxLength(20)
                .HasColumnName("visibility");
            entity.Property(e => e.Year).HasColumnName("year");
        });

        OnModelCreatingPartial(modelBuilder);
    }

    partial void OnModelCreatingPartial(ModelBuilder modelBuilder);
}
