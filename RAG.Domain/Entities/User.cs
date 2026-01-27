using System;
using System.Collections.Generic;

namespace RAG.Domain    .Entities;

public partial class User
{
    public Guid Id { get; set; }

    //Mã định danh của tài khoản trong cognito
    public string CognitoSub { get; set; } = null!;
    public Guid Roleid { get; set; }

    public string Email { get; set; } = null!;

    public string? FullName { get; set; }

    public virtual Role Role { get; set; } = null!;
}
