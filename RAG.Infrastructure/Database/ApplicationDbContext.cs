using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using RAG.Infrastructure;
using System;
using System.Collections.Generic;

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

    public virtual DbSet<ChatSession> ChatSessions { get; set; }

    public virtual DbSet<Company> Companies { get; set; }

    public virtual DbSet<QuestionPrompt> QuestionPrompts { get; set; }

    public virtual DbSet<RatioDefinition> RatioDefinitions { get; set; }

    public virtual DbSet<RatioGroup> RatioGroups { get; set; }

    public virtual DbSet<RatioValue> RatioValues { get; set; }

    public virtual DbSet<Regulation> Regulations { get; set; }

    public virtual DbSet<ReportCategory> ReportCategories { get; set; }

    public virtual DbSet<ReportFinancial> ReportFinancials { get; set; }

    public virtual DbSet<Role> Roles { get; set; }

    public virtual DbSet<Source> Sources { get; set; }

    public virtual DbSet<User> Users { get; set; }


    //    protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
    //#warning To protect potentially sensitive information in your connection string, you should move it out of source code. You can avoid scaffolding the connection string by using the Name= syntax to read it from configuration - see https://go.microsoft.com/fwlink/?linkid=2131148. For more guidance on storing connection strings, see https://go.microsoft.com/fwlink/?LinkId=723263.
    //        => optionsBuilder.UseNpgsql("Host=localhost;Port=5432;Database=postgres;Username=postgres;Password=123456", x => x.UseVector());

    public static string GetConnectionString(string connectionStringName)
    {
        var config = new ConfigurationBuilder()
            .SetBasePath(AppDomain.CurrentDomain.BaseDirectory)
            .AddJsonFile("appsettings.json")
            .Build();

        string connectionString = config.GetConnectionString(connectionStringName);
        return connectionString;
    }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<AnalyticsReport>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("Analytics_Report_pkey");

            entity.Property(e => e.Id).HasDefaultValueSql("gen_random_uuid()");
            entity.Property(e => e.CreatedAt).HasDefaultValueSql("now()");

            entity.HasOne(d => d.ReportFinancial).WithMany(p => p.AnalyticsReports)
                .OnDelete(DeleteBehavior.SetNull)
                .HasConstraintName("FK_Analytics_Report");
        });

        modelBuilder.Entity<ChatSession>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("Chat_Sessions_pkey");

            entity.Property(e => e.Id).HasDefaultValueSql("gen_random_uuid()");
            entity.Property(e => e.StartTime).HasDefaultValueSql("now()");

            entity.HasOne(d => d.User).WithMany(p => p.ChatSessions).HasConstraintName("FK_Chat_User");
        });

        modelBuilder.Entity<Company>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("Company_pkey");

            entity.Property(e => e.Id).HasDefaultValueSql("gen_random_uuid()");
        });

        modelBuilder.Entity<QuestionPrompt>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("Question_Prompt_pkey");

            entity.Property(e => e.Id).HasDefaultValueSql("gen_random_uuid()");
            entity.Property(e => e.CreatedAt).HasDefaultValueSql("now()");

            entity.HasOne(d => d.Session).WithMany(p => p.QuestionPrompts).HasConstraintName("FK_Prompt_Session");

            entity.HasMany(d => d.Analytics).WithMany(p => p.Prompts)
                .UsingEntity<Dictionary<string, object>>(
                    "PromptAnalytic",
                    r => r.HasOne<AnalyticsReport>().WithMany()
                        .HasForeignKey("AnalyticsId")
                        .HasConstraintName("FK_PA_Analytics"),
                    l => l.HasOne<QuestionPrompt>().WithMany()
                        .HasForeignKey("PromptId")
                        .HasConstraintName("FK_PA_Prompt"),
                    j =>
                    {
                        j.HasKey("PromptId", "AnalyticsId").HasName("Prompt_Analytics_pkey");
                        j.ToTable("Prompt_Analytics");
                    });

            entity.HasMany(d => d.RatioValues).WithMany(p => p.Prompts)
                .UsingEntity<Dictionary<string, object>>(
                    "PromptRatioValue",
                    r => r.HasOne<RatioValue>().WithMany()
                        .HasForeignKey("RatioValueId")
                        .HasConstraintName("FK_PRV_Ratio"),
                    l => l.HasOne<QuestionPrompt>().WithMany()
                        .HasForeignKey("PromptId")
                        .HasConstraintName("FK_PRV_Prompt"),
                    j =>
                    {
                        j.HasKey("PromptId", "RatioValueId").HasName("Prompt_RatioValues_pkey");
                        j.ToTable("Prompt_RatioValues");
                    });
        });

        modelBuilder.Entity<RatioDefinition>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("Ratio_Definition_pkey");

            entity.Property(e => e.Id).HasDefaultValueSql("gen_random_uuid()");

            entity.HasOne(d => d.Group).WithMany(p => p.RatioDefinitions).HasConstraintName("FK_RatioDef_Group");

            entity.HasOne(d => d.Parent).WithMany(p => p.InverseParent).HasConstraintName("FK_RatioDef_Parent");
        });

        modelBuilder.Entity<RatioGroup>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("Ratio_Group_pkey");

            entity.Property(e => e.Id).HasDefaultValueSql("gen_random_uuid()");
        });

        modelBuilder.Entity<RatioValue>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("Ratio_Value_pkey");

            entity.Property(e => e.Id).HasDefaultValueSql("gen_random_uuid()");

            entity.HasOne(d => d.Definition).WithMany(p => p.RatioValues).HasConstraintName("FK_RatioVal_Def");

            entity.HasOne(d => d.Report).WithMany(p => p.RatioValues).HasConstraintName("FK_RatioVal_Report");
        });

        modelBuilder.Entity<Regulation>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("Regulation_pkey");

            entity.Property(e => e.Id).HasDefaultValueSql("gen_random_uuid()");

            entity.HasMany(d => d.Sources).WithMany(p => p.Regulations)
                .UsingEntity<Dictionary<string, object>>(
                    "RegulationSource",
                    r => r.HasOne<Source>().WithMany()
                        .HasForeignKey("SourceId")
                        .HasConstraintName("FK_RS_Source"),
                    l => l.HasOne<Regulation>().WithMany()
                        .HasForeignKey("RegulationId")
                        .HasConstraintName("FK_RS_Regulation"),
                    j =>
                    {
                        j.HasKey("RegulationId", "SourceId").HasName("Regulation_Sources_pkey");
                        j.ToTable("Regulation_Sources");
                    });
        });

        modelBuilder.Entity<ReportCategory>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("Report_Category_pkey");

            entity.Property(e => e.Id).HasDefaultValueSql("gen_random_uuid()");
        });

        modelBuilder.Entity<ReportFinancial>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("Report_Financial_pkey");

            entity.Property(e => e.Id).HasDefaultValueSql("gen_random_uuid()");

            entity.HasOne(d => d.Category).WithMany(p => p.ReportFinancials).HasConstraintName("FK_Report_Category");

            entity.HasOne(d => d.Company).WithMany(p => p.ReportFinancials).HasConstraintName("FK_Report_Company");

            entity.HasOne(d => d.Source).WithMany(p => p.ReportFinancials)
                .OnDelete(DeleteBehavior.SetNull)
                .HasConstraintName("FK_Report_Source");
        });

        modelBuilder.Entity<Role>(entity =>
        {
            entity.ToTable("Roles");

            entity.Property(e => e.Id).HasColumnName("Id");
            entity.Property(e => e.Name).HasColumnName("Name");
        });

        modelBuilder.Entity<Source>(entity =>
        {
            entity.HasKey(e => e.Id).HasName("Sources_pkey");

            entity.Property(e => e.Id).HasDefaultValueSql("gen_random_uuid()");
        });

        modelBuilder.Entity<User>(entity =>
        {
            entity.ToTable("Users");
            entity.Property(e => e.Id).HasColumnName("Id");
            entity.Property(e => e.RoleId).HasColumnName("RoleId");
            entity.Property(e => e.FullName).HasColumnName("FullName");
            entity.Property(e => e.Email).HasColumnName("Email");
            entity.Property(e => e.CognitoSub).HasColumnName("CognitoSub");

            entity.HasOne(d => d.Role)
                  .WithMany(p => p.Users)
                  .HasForeignKey(d => d.RoleId)
                  .OnDelete(DeleteBehavior.ClientSetNull)
                  .HasConstraintName("FK_Chat_User");
        });

        OnModelCreatingPartial(modelBuilder);
    }

    partial void OnModelCreatingPartial(ModelBuilder modelBuilder);
}
