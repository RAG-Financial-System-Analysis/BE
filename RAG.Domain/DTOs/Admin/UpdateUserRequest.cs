using System;

namespace RAG.Domain.DTOs.Admin
{
    public class UpdateUserRequest
    {
        public string FullName { get; set; } = string.Empty;
        public string Role { get; set; } = string.Empty; // Changed from RoleId to Role name
        public bool IsActive { get; set; }
    }
}
