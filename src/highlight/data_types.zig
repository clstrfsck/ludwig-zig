pub const Detect = struct {
    filename: ?[]const u8 = null,
    header: ?[]const u8 = null,
    signature: ?[]const u8 = null,
};

pub const PatternRule = struct {
    group: []const u8,
    regex: []const u8,
};

pub const RegionRule = struct {
    group: []const u8,
    start: []const u8,
    end: []const u8,
    skip: ?[]const u8 = null,
    limit_group: ?[]const u8 = null,
    rules: []const Rule = &.{},
};

pub const Rule = union(enum) {
    include: []const u8,
    pattern: PatternRule,
    region: RegionRule,
};

pub const SyntaxFile = struct {
    filetype: []const u8,
    detect: Detect = .{},
    rules: []const Rule = &.{},
};
