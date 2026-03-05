using System.Collections.Generic;

namespace RAG.Domain.DTOs.Admin
{
    public class SystemStatisticsResponse
    {
        public UsersStat Users { get; set; } = new();
        public ReportsStat Reports { get; set; } = new();
        public ChatSessionsStat ChatSessions { get; set; } = new();
        public StorageStat Storage { get; set; } = new();
    }

    public class UsersStat
    {
        public int Total { get; set; }
        public int Active { get; set; }
        public Dictionary<string, int> ByRole { get; set; } = new();
    }

    public class ReportsStat
    {
        public int Total { get; set; }
        public int Public { get; set; }
        public int Private { get; set; }
    }

    public class ChatSessionsStat
    {
        public int Total { get; set; }
        public int ActiveToday { get; set; }
    }

    public class StorageStat
    {
        public double TotalSizeGB { get; set; }
        public int FilesCount { get; set; }
    }
}
