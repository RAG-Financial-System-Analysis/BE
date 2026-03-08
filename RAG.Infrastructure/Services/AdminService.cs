using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
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
    }
}
