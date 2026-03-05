using System;

namespace RAG.Domain.DTOs.Admin
{
    public class UserStatisticsDto
    {
        public int ReportsUploaded { get; set; }
        public int ChatSessions { get; set; }
    }

    public class GetUserByIdResponse
    {
        public Guid Id { get; set; }
        public string Email { get; set; } = string.Empty;
        public string FullName { get; set; } = string.Empty;
        public RoleDto Role { get; set; } = new();
        public bool IsActive { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? LastLoginAt { get; set; }
        public UserStatisticsDto Statistics { get; set; } = new();
    }
}
