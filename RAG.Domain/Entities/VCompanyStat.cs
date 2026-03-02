using System;
using System.Collections.Generic;

namespace RAG.Domain;

public partial class VCompanyStat
{
    public Guid? Id { get; set; }

    public string? Ticker { get; set; }

    public string? Name { get; set; }

    public string? Industry { get; set; }

    public long? Totalreports { get; set; }

    public long? Publicreports { get; set; }

    public int? Earliestyear { get; set; }

    public int? Latestyear { get; set; }

    public long? Totalratios { get; set; }
}
