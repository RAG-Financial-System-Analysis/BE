using System;
using System.Collections.Generic;

namespace RAG.Domain.DTOs.Admin
{
    public class AuditLogItemDto
    {
        public Guid Id { get; set; }
        public Guid? UserId { get; set; }
        public string UserName { get; set; } = string.Empty;
        public string Action { get; set; } = string.Empty;
        public string ResourceType { get; set; } = string.Empty;
        public Guid? ResourceId { get; set; }
        public string Details { get; set; } = string.Empty;
        public string IpAddress { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
    }

    public class GetAuditLogsResponse
    {
        public int Total { get; set; }
        public int Page { get; set; }
        public int PageSize { get; set; }
        public List<AuditLogItemDto> Data { get; set; } = new();
    }
}
