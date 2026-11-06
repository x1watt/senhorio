// Roles of the people sharing a building, and what each may do.
//
//   owner  created the building (one, immutable); can do everything
//   admin  a co-owner: everything, except changing the owner's membership
//   mod    runs the day to day (rooms, leases, rents, expenses); can invite
//          and revoke tenants only
//   user   a tenant: sees only the building, their own lease and payments
//          and who manages it; changes nothing
//
// Rows written before roles existed say 'member': they act as mods.

enum Role { owner, admin, mod, user }

Role? roleOf(Object? s) => switch (s) {
      'owner' => Role.owner,
      'admin' => Role.admin,
      'mod' || 'member' => Role.mod,
      'user' => Role.user,
      _ => null,
    };

extension RoleRules on Role {
  /// Sees and changes all of the building's data.
  bool get isStaff => this != Role.user;

  /// May write rows of [entity] (other than `members`).
  bool canWrite(String entity) => isStaff;

  /// May delete the building itself.
  bool get canDeleteBuilding => this == Role.owner || this == Role.admin;

  /// Roles this role may hand out with an invite or a role change.
  List<Role> get canGrant => switch (this) {
        Role.owner || Role.admin => const [Role.admin, Role.mod, Role.user],
        Role.mod => const [Role.user],
        Role.user => const [],
      };

  /// May change or revoke the membership of someone whose role is [target]
  /// (null: no membership yet), giving them [to] (null: role unchanged).
  bool canManage(Role? target, Role? to) {
    if (target == Role.owner || to == Role.owner) return false;
    final grant = canGrant;
    if (grant.isEmpty) return false;
    if (target != null && !grant.contains(target)) return false;
    if (to != null && !grant.contains(to)) return false;
    return true;
  }
}
