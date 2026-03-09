using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
using RAG.Domain;
using RAG.Domain.DTOs.Admin;
using RAG.Infrastructure.Database;
using System;
using System.Linq;
using System.Threading.Tasks;

namespace RAG.Infrastructure.Services
{
    public class AdminService : IAdminService
    {
        private readonly ApplicationDbContext _dbContext;

        public AdminService(ApplicationDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        public async Task<GetAuditLogsResponse> GetAuditLogsAsync(Guid? userId, string action, DateTime? startDate, DateTime? endDate, int page, int pageSize)
        {
            var query = _dbContext.AuditLogs.Include(a => a.User).AsQueryable();

            if (userId.HasValue)
            {
                query = query.Where(a => a.Userid == userId.Value);
            }

            if (!string.IsNullOrEmpty(action))
            {
                query = query.Where(a => a.Action.ToLower() == action.ToLower());
            }

            if (startDate.HasValue)
            {
                query = query.Where(a => a.Createdat >= startDate.Value);
            }

            if (endDate.HasValue)
            {
                query = query.Where(a => a.Createdat <= endDate.Value);
            }

            var total = await query.CountAsync();

            var data = await query
                .OrderByDescending(a => a.Createdat)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(a => new AuditLogItemDto
                {
                    Id = a.Id,
                    UserId = a.Userid,
                    UserName = a.User != null ? (a.User.Fullname ?? string.Empty) : string.Empty,
                    Action = a.Action,
                    ResourceType = a.Resourcetype ?? string.Empty,
                    ResourceId = a.Resourceid,
                    Details = a.Details ?? string.Empty,
                    IpAddress = a.Ipaddress ?? string.Empty,
                    CreatedAt = a.Createdat ?? DateTime.MinValue
                })
                .ToListAsync();

            return new GetAuditLogsResponse
            {
                Total = total,
                Page = page,
                PageSize = pageSize,
                Data = data
            };
        }

        public async Task<SystemStatisticsResponse> GetSystemStatisticsAsync()
        {
            // 1. Users Statistics
            var usersQuery = _dbContext.Users.Include(u => u.Role).AsNoTracking();
            var totalUsers = await usersQuery.CountAsync();
            var activeUsers = await usersQuery.CountAsync(u => u.Isactive == true);
            var usersByRole = await usersQuery
                .Where(u => u.Role != null)
                .GroupBy(u => u.Role.Name)
                .Select(g => new { RoleName = g.Key, Count = g.Count() })
                .ToDictionaryAsync(g => g.RoleName, g => g.Count);

            // 2. Reports Statistics
            var reportsQuery = _dbContext.ReportFinancials.AsNoTracking();
            var totalReports = await reportsQuery.CountAsync();
            var publicReports = await reportsQuery.CountAsync(r => r.Visibility == "public");
            var privateReports = await reportsQuery.CountAsync(r => r.Visibility == "private");

            // 3. Chat Sessions Statistics
            var chatsQuery = _dbContext.ChatSessions.AsNoTracking();
            var totalChats = await chatsQuery.CountAsync();

            var today = DateTime.SpecifyKind(DateTime.UtcNow.Date, DateTimeKind.Unspecified);
            var activeTodayChats = await chatsQuery.CountAsync(c => c.Createdat >= today);

            // 4. Storage Statistics
            var totalSizeKb = await reportsQuery.SumAsync(r => (long)(r.Filesizekb ?? 0));
            var totalSizeGb = totalSizeKb / (double)(1024 * 1024);
            var filesCount = totalReports;

            return new SystemStatisticsResponse
            {
                Users = new UsersStat
                {
                    Total = totalUsers,
                    Active = activeUsers,
                    ByRole = usersByRole
                },
                Reports = new ReportsStat
                {
                    Total = totalReports,
                    Public = publicReports,
                    Private = privateReports
                },
                ChatSessions = new ChatSessionsStat
                {
                    Total = totalChats,
                    ActiveToday = activeTodayChats
                },
                Storage = new StorageStat
                {
                    TotalSizeGB = Math.Round(totalSizeGb, 2),
                    FilesCount = filesCount
                }
            };
        }
        public async Task<CreateReportCategoriesResponse> CreateReportCategoryAsync(CreateReportCategoriesRequest request)
        {
            var exists = await _dbContext.ReportCategories.AnyAsync(c => c.Name == request.Name);
            if (exists)
            {
                throw new ArgumentException("Name already exists");
            }

            var category = new ReportCategory
            {
                Id = Guid.NewGuid(),
                Name = request.Name,
                Description = request.Description
            };
            _dbContext.ReportCategories.Add(category);
            await _dbContext.SaveChangesAsync();
            return new CreateReportCategoriesResponse
            {
                Id = category.Id,
                Message = "Report category created successfully"
            };
        }

        public async Task<GetReportCategoriesResponse> GetReportCategoriesAsync(int page, int pageSize)
        {
            var query = _dbContext.ReportCategories.AsNoTracking();
            var total = await query.CountAsync();
            
            var data = await query
                .Select(c => new ReportCategoryDto
                {
                    Id = c.Id,
                    Name = c.Name,
                    Description = c.Description,
                    AssociatedReportsCount = c.ReportFinancials.Count
                })
                .OrderBy(c => c.Name)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            return new GetReportCategoriesResponse
            {
                Total = total,
                Page = page,
                PageSize = pageSize,
                Data = data
            };
        }

        public async Task<GetReportCategoryByIdResponse> GetReportCategoryByIdAsync(Guid id)
        {
            var category = await _dbContext.ReportCategories
                .AsNoTracking()
                .Include(c => c.ReportFinancials)
                    .ThenInclude(r => r.Company)
                .FirstOrDefaultAsync(c => c.Id == id);

            if (category == null)
                throw new KeyNotFoundException("Report category not found");

            return new GetReportCategoryByIdResponse
            {
                Id = category.Id,
                Name = category.Name,
                Description = category.Description,
                AssociatedReportsCount = category.ReportFinancials.Count,
                AssociatedReports = category.ReportFinancials.Select(r => new AssociatedReportDto
                {
                    Id = r.Id,
                    Title = r.Filename ?? $"{r.Company.Name} {r.Period}/{r.Year}",
                    CompanyName = r.Company.Name ?? string.Empty,
                    CreatedAt = r.Createdat
                }).ToList()
            };
        }

        public async Task UpdateReportCategoryAsync(Guid id, UpdateReportCategoryRequest request)
        {
            var category = await _dbContext.ReportCategories.FindAsync(id);
            if (category == null)
                throw new KeyNotFoundException("Report category not found");

            var nameExists = await _dbContext.ReportCategories
                .AnyAsync(c => c.Name == request.Name && c.Id != id);
            if (nameExists)
                throw new ArgumentException("Name already exists");

            category.Name = request.Name;
            category.Description = request.Description;

            _dbContext.ReportCategories.Update(category);
            await _dbContext.SaveChangesAsync();
        }

        public async Task DeleteReportCategoryAsync(Guid id)
        {
            var category = await _dbContext.ReportCategories
                .Include(c => c.ReportFinancials)
                .FirstOrDefaultAsync(c => c.Id == id);

            if (category == null)
                throw new KeyNotFoundException("Report category not found");

            if (category.ReportFinancials.Any())
                throw new InvalidOperationException("Cannot delete report category because it has associated financial reports");

            _dbContext.ReportCategories.Remove(category);
            await _dbContext.SaveChangesAsync();
        }

        public async Task<GetReportCategoriesForAnalystResponse> GetReportCategoriesForAnalystAsync()
        {
            var categories = await _dbContext.ReportCategories
                .AsNoTracking()
                .OrderBy(c => c.Name)
                .Select(c => new ReportCategorySimpleDto
                {
                    Id = c.Id,
                    Name = c.Name,
                    Description = c.Description
                })
                .ToListAsync();

            return new GetReportCategoriesForAnalystResponse { Categories = categories };
        }

        public async Task<CreateAnalyticsTypeResponse> CreateAnalyticsTypeAsync(CreateAnalyticsTypeRequest request)
        {
            var exists = await _dbContext.AnalyticsTypes.AnyAsync(t => t.Code == request.Code);
            if (exists)
                throw new ArgumentException("Code already exists");

            var analyticsType = new AnalyticsType
            {
                Id = Guid.NewGuid(),
                Code = request.Code,
                Name = request.Name,
                Description = request.Description,
                Createdat = DateTime.SpecifyKind(DateTime.UtcNow, DateTimeKind.Unspecified)
            };

            _dbContext.AnalyticsTypes.Add(analyticsType);
            await _dbContext.SaveChangesAsync();

            return new CreateAnalyticsTypeResponse
            {
                Id = analyticsType.Id,
                Message = "Analytics type created successfully"
            };
        }

        public async Task UpdateAnalyticsTypeAsync(Guid id, UpdateAnalyticsTypeRequest request)
        {
            var analyticsType = await _dbContext.AnalyticsTypes.FindAsync(id);
            if (analyticsType == null)
                throw new KeyNotFoundException("Analytics type not found");

            var codeExists = await _dbContext.AnalyticsTypes
                .AnyAsync(t => t.Code == request.Code && t.Id != id);
            if (codeExists)
                throw new ArgumentException("Code already exists");

            analyticsType.Code = request.Code;
            analyticsType.Name = request.Name;
            analyticsType.Description = request.Description;
            // Createdat is not updated intentionally

            _dbContext.AnalyticsTypes.Update(analyticsType);
            await _dbContext.SaveChangesAsync();
        }

        public async Task DeleteAnalyticsTypeAsync(Guid id)
        {
            var analyticsType = await _dbContext.AnalyticsTypes
                .Include(t => t.ChatSessions)
                .FirstOrDefaultAsync(t => t.Id == id);

            if (analyticsType == null)
                throw new KeyNotFoundException("Analytics type not found");

            if (analyticsType.ChatSessions.Any())
                throw new InvalidOperationException("Cannot delete analytics type with associated chat sessions");

            _dbContext.AnalyticsTypes.Remove(analyticsType);
            await _dbContext.SaveChangesAsync();
        }
    }
}
