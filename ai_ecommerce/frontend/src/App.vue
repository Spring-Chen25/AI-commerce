<script setup>
import { computed, nextTick, onMounted, reactive, ref } from 'vue'

const groups = [
  { name: '平台配置', accent: 'waypoint', items: [{ key: 'shops', title: '店铺管理', icon: '◈' }, { key: 'platforms', title: '平台连接', icon: '⌁' }] },
  { name: '用户管理', accent: 'terraform', items: [{ key: 'users', title: '用户管理', icon: '♙' }, { key: 'roles', title: '角色管理', icon: '◇' }, { key: 'departments', title: '部门管理', icon: '⌘' }, { key: 'permissions', title: '权限目录', icon: '⊙' }] },
  { name: '租户管理', accent: 'vault', items: [{ key: 'orgs', title: '租户列表', icon: '▣' }] },
]
const screens = {
  shops: { group: '平台配置', path: '/rbac/shops', title: '店铺管理', intro: '店铺可由多个部门分管；分管关系在「部门管理 → 店铺分配」中维护。', columns: [['shop_code', '店铺编码'], ['shop_name', '店铺名称'], ['platform', '平台'], ['dept_names', '分管部门'], ['status', '状态']], fields: [['shop_code', '店铺编码', 'text', true], ['shop_name', '店铺名称', 'text', true], ['platform', '平台', 'text', true], ['dept_id', '主归属部门', 'department'], ['status', '状态', 'status']] },
  platforms: { group: '平台配置', path: '/rbac/platform-configs', title: '平台连接', intro: '为店铺维护 API 连接信息；密钥加密保存并在列表中脱敏。', columns: [['shop_id', '店铺'], ['platform', '平台'], ['api_base_url', 'API 地址'], ['api_key_masked', 'API Key'], ['status', '状态']], fields: [['shop_id', '店铺', 'shop', true], ['platform', '平台', 'text', true], ['api_base_url', 'API 地址', 'url'], ['callback_url', '回调地址', 'url'], ['api_key', 'API Key', 'password'], ['api_secret', 'API Secret', 'password'], ['access_token', 'Access Token', 'password'], ['status', '状态', 'status']] },
  users: { group: '用户管理', path: '/rbac/users', title: '用户管理', intro: '成员归属部门，通过角色获得所需访问权限。', columns: [['username', '用户名'], ['real_name', '真实姓名'], ['email', '邮箱'], ['phone', '手机号'], ['role_names', '角色'], ['dept_id', '部门'], ['status', '状态']], fields: [['username', '用户名', 'text', true], ['real_name', '姓名', 'text', true], ['dept_id', '所属部门', 'department'], ['email', '邮箱', 'email'], ['phone', '联系电话', 'text'], ['password', '初始密码', 'password', true], ['data_scope', '数据范围', 'scope'], ['status', '状态', 'status']] },
  roles: { group: '用户管理', path: '/rbac/roles', title: '角色管理', intro: '按职责授权，使用权限目录中的编码组合角色能力。', columns: [['role_code', '角色编码'], ['role_name', '角色名称'], ['description', '业务职责'], ['sort', '排序'], ['permission_keys', '权限数'], ['status', '状态']], fields: [['role_code', '角色编码', 'text', true], ['role_name', '角色名称', 'text', true], ['description', '业务职责', 'textarea'], ['data_scope', '数据范围', 'scope'], ['status', '状态', 'status']] },
  permissions: { group: '用户管理', path: '/rbac/permissions', title: '权限目录', intro: '权限编码和业务说明由项目权限表维护。', columns: [['perm_key', '权限编码'], ['perm_name', '权限名称'], ['description', '业务说明'], ['perm_type', '类型'], ['status', '状态']], readOnly: true },
  departments: { group: '用户管理', path: '/rbac/departments', title: '部门管理', intro: '总公司为根节点，直属部门、成员和店铺在同一租户内关联。', columns: [['dept_code', '部门编码'], ['dept_name', '部门名称'], ['parent_id', '上级部门'], ['manager_name', '负责人'], ['manager_status', '负责人状态'], ['phone', '联系电话'], ['user_count', '成员'], ['shop_ids', '分配店铺']], fields: [['dept_code', '部门编码', 'text', true], ['dept_name', '部门名称', 'text', true], ['parent_id', '上级部门', 'parent'], ['manager_id', '负责人', 'manager'], ['phone', '联系电话', 'text'], ['email', '部门邮箱', 'email'], ['status', '状态', 'status']] },
  orgs: { group: '租户管理', path: '/system/orgs', title: '租户管理', intro: '管理各租户状态与基础资料，新增租户会初始化角色目录。', columns: [['org_code', '租户编码'], ['org_name', '租户名称'], ['package_code', '套餐'], ['data_region', '数据区域'], ['status', '状态']], fields: [['org_code', '租户编码', 'text', true], ['org_name', '租户名称', 'text', true], ['domain', '域名', 'text'], ['package_code', '套餐', 'text'], ['data_region', '数据区域', 'text'], ['status', '状态', 'orgStatus']] },
}

const token = ref(sessionStorage.getItem('rbacToken') || '')
const currentUser = ref(null)
const login = reactive({ org_code: 'RBAC_TEST', username: 'admin', password: '' })
const loginError = ref('')
const authMode = ref('login')
const registerForm = reactive({ org_code: 'RBAC_TEST', username: '', real_name: '', email: '', phone: '', password: '', confirm_password: '' })
const registrationError = ref('')
const registrationNotice = ref('')
const registering = ref(false)
const screenKey = ref('shops')
const rows = ref([])
const departments = ref([])
const managerCandidates = ref([])
const shops = ref([])
const roles = ref([])
const permissions = ref([])
const myPermissions = ref([])
const users = ref([])
const loading = ref(false)
const error = ref('')
const search = ref('')
const userKeyword = ref('')
const userStatus = ref('')
const appliedUserKeyword = ref('')
const appliedUserStatus = ref('')
const userPage = ref(1)
const userPageSize = ref(20)
const modal = ref('')
const editing = ref(null)
const form = reactive({})
const selected = ref([])
const operationError = ref('')
const saving = ref(false)
const temporaryPassword = ref('')
const expandedModules = ref([])
function groupPermissions(items) {
  const grouped = new Map()
  for (const item of items) {
    const name = item.module_name || '未分类'
    if (!grouped.has(name)) grouped.set(name, [])
    grouped.get(name).push(item)
  }
  return Array.from(grouped, ([name, items]) => ({ name, items }))
}
const permissionGroups = computed(() => groupPermissions(permissions.value))
const myAgentGroups = computed(() => groupPermissions(myPermissions.value).filter(group => group.name.endsWith('Agent')))
const isModuleScreen = computed(() => screenKey.value.startsWith('module:'))
const screen = computed(() => isModuleScreen.value
  ? { group: 'Agent 模块', title: screenKey.value.slice(7), intro: '当前账号已获授权的具体权限。', columns: [['perm_name', '权限名称'], ['perm_key', '权限编码'], ['description', '业务说明']], readOnly: true }
  : screens[screenKey.value])
const canManage = computed(() => !!currentUser.value?.roles?.includes('SUPER_ADMIN') || !!currentUser.value?.permissions?.includes('system:org:roleManage'))
const visibleGroups = computed(() => [
  ...(canManage.value ? groups : []),
  ...(myAgentGroups.value.length ? [{ name: 'Agent 模块', items: myAgentGroups.value.map(group => ({ key: `module:${group.name}`, title: group.name, icon: '◈' })) }] : []),
])
const entityLabel = computed(() => ({ users: '用户', roles: '角色', departments: '部门', orgs: '租户', shops: '店铺', platforms: '连接' })[screenKey.value] || screen.value.title)
const visibleRows = computed(() => {
  if (screenKey.value === 'users') {
    const keyword = appliedUserKeyword.value.toLocaleLowerCase()
    return rows.value.filter(row =>
      (!keyword || [row.username, row.real_name, row.email].some(value => String(value ?? '').toLocaleLowerCase().includes(keyword))) &&
      (!appliedUserStatus.value || row.status === appliedUserStatus.value)
    )
  }
  const keyword = search.value.trim().toLocaleLowerCase()
  return rows.value.filter(row => Object.values(row).some(value => String(value ?? '').toLocaleLowerCase().includes(keyword)))
})
const userPageCount = computed(() => Math.max(1, Math.ceil(visibleRows.value.length / userPageSize.value)))
const paginatedRows = computed(() => screenKey.value === 'users'
  ? visibleRows.value.slice((userPage.value - 1) * userPageSize.value, userPage.value * userPageSize.value)
  : visibleRows.value)
const catalogGroups = computed(() => groupPermissions(visibleRows.value))
function applyUserFilters() {
  appliedUserKeyword.value = userKeyword.value.trim()
  appliedUserStatus.value = userStatus.value
  userPage.value = 1
}
function resetUserFilters() {
  userKeyword.value = ''
  userStatus.value = ''
  applyUserFilters()
}
function setUserPage(value) {
  const page = Number(value)
  if (Number.isInteger(page)) userPage.value = Math.min(Math.max(page, 1), userPageCount.value)
}
const departmentNames = computed(() => Object.fromEntries(departments.value.map(item => [item.id, item.dept_name])))
const shopNames = computed(() => Object.fromEntries(shops.value.map(item => [item.id, item.shop_name])))

async function api(path, options = {}) {
  const response = await fetch(`/api/v1${path}`, { ...options, headers: { 'Content-Type': 'application/json', ...(token.value ? { Authorization: `Bearer ${token.value}` } : {}), ...options.headers } })
  const body = await response.json().catch(() => ({}))
  if (!response.ok || body.code !== 200) throw new Error(body.message || `请求失败（HTTP ${response.status}）`)
  return body.data
}
async function signIn() {
  loginError.value = ''
  try {
    const result = await api('/auth/login', { method: 'POST', body: JSON.stringify(login) })
    token.value = result.access_token
    sessionStorage.setItem('rbacToken', token.value)
    login.password = ''
    currentUser.value = await api('/auth/me')
    myPermissions.value = await api('/rbac/my-permissions')
    if (!canManage.value && myAgentGroups.value.length) screenKey.value = `module:${myAgentGroups.value[0].name}`
    if (canManage.value || isModuleScreen.value) await loadScreen()
    else { rows.value = []; error.value = '' }
  } catch (cause) { signOut(); loginError.value = cause.message }
}
function openRegistration() {
  registerForm.org_code = login.org_code
  registrationError.value = ''
  registrationNotice.value = ''
  authMode.value = 'register'
  nextTick(() => window.scrollTo(0, 0))
}
function returnToLogin() {
  registrationError.value = ''
  authMode.value = 'login'
  nextTick(() => window.scrollTo(0, 0))
}
async function signUp() {
  registrationError.value = ''
  if (registerForm.password !== registerForm.confirm_password) {
    registrationError.value = '两次输入的密码不一致'
    return
  }
  registering.value = true
  try {
    const result = await api('/auth/register', { method: 'POST', body: JSON.stringify(registerForm) })
    login.org_code = registerForm.org_code
    login.username = registerForm.username
    login.password = ''
    registerForm.password = ''
    registerForm.confirm_password = ''
    registrationNotice.value = result.message || '注册成功，请等待管理员启用账号并分配角色'
    authMode.value = 'login'
  } catch (cause) { registrationError.value = cause.message }
  finally { registering.value = false }
}
function signOut() { token.value = ''; currentUser.value = null; sessionStorage.removeItem('rbacToken'); rows.value = []; myPermissions.value = [] }
async function refreshLookups() {
  if (!currentUser.value?.permissions.includes('system:org:roleManage') && !currentUser.value?.roles.includes('SUPER_ADMIN')) return
  const paths = ['/rbac/departments', '/rbac/shops', '/rbac/roles', '/rbac/permissions', '/rbac/users', '/rbac/departments/manager-candidates']
  const result = await Promise.all(paths.map(path => api(path)))
  ;[departments.value, shops.value, roles.value, permissions.value, users.value, managerCandidates.value] = result
}
async function loadScreen() {
  if (isModuleScreen.value) {
    rows.value = myAgentGroups.value.find(group => group.name === screen.value.title)?.items || []
    error.value = ''
    return
  }
  if (!canManage.value) { rows.value = []; error.value = ''; return }
  loading.value = true; error.value = ''
  try {
    await refreshLookups()
    rows.value = await api(screen.value.path)
  } catch (cause) { error.value = cause.message; rows.value = [] }
  finally { loading.value = false }
}
function navigate(key) { if (!canManage.value && !myAgentGroups.value.some(group => key === `module:${group.name}`)) return; screenKey.value = key; search.value = ''; resetUserFilters(); loadScreen() }
function display(row, key) {
  const value = row[key]
  if (key === 'role_names') {
    const names = Array.isArray(value) && value.length ? value : (row.role_codes || []).map(code => roles.value.find(role => role.role_code === code)?.role_name || code)
    return names.join('、') || '未分配'
  }
  if (key === 'dept_id') return departmentNames.value[value] || (value == null ? '—' : `#${value}`)
  if (key === 'dept_names') return Array.isArray(value) && value.length ? value.join('、') : '未分配'
  if (key === 'parent_id') return value === 0 ? '根节点' : departmentNames.value[value] || `#${value}`
  if (key === 'manager_status') return { UNASSIGNED: '待指派', ENABLED: '在职', DISABLED: '已停用' }[value] || '待指派'
  if (key === 'shop_id') return shopNames.value[value] || `#${value}`
  if (key === 'shop_ids') return Array.isArray(value) ? value.map(id => shopNames.value[id] || `#${id}`).join('、') || '未分配' : '—'
  if (key === 'permission_keys') return `${value?.length || 0} 项权限`
  if (key === 'user_count') return `${users.value.filter(user => user.dept_id === row.id).length} 人`
  if (Array.isArray(value)) return value.join('、') || '—'
  return value === null || value === undefined || value === '' ? '—' : String(value)
}
function openEditor(row = null) {
  editing.value = row; operationError.value = ''; Object.keys(form).forEach(key => delete form[key])
  for (const [key, , type] of screen.value.fields) {
    form[key] = row?.[key] ?? (key === 'status' ? (screenKey.value === 'orgs' ? 'ACTIVE' : 'ENABLED') : key === 'data_scope' ? 'SELF' : key === 'parent_id' || key === 'sort' ? 0 : '')
    if (type === 'password') form[key] = ''
    if (type === 'manager') form[key] = row?.[key] == null ? '' : String(row[key])
  }
  modal.value = 'editor'
}
function closeModal() { modal.value = ''; editing.value = null; operationError.value = ''; selected.value = []; temporaryPassword.value = '' }
async function saveEditor() {
  saving.value = true; operationError.value = ''
  const payload = { ...form }
  for (const key of ['dept_id', 'parent_id', 'shop_id', 'sort', 'manager_id']) {
    if (key === 'dept_id' && (payload[key] === '' || payload[key] === null)) payload[key] = null
    else if (key === 'manager_id' && (payload[key] === '' || payload[key] === null)) payload[key] = null
    else if (payload[key] === '' || payload[key] === null) delete payload[key]
    else if (key in payload) payload[key] = Number(payload[key])
  }
  if (screenKey.value === 'users') {
    for (const key of ['email', 'phone']) if (typeof payload[key] === 'string' && !payload[key].trim()) payload[key] = null
  }
  for (const key of ['password', 'api_key', 'api_secret', 'access_token']) if (!payload[key]) delete payload[key]
  if (screenKey.value === 'users' && editing.value) delete payload.username
  if (editing.value && (screenKey.value === 'roles' || screenKey.value === 'departments')) payload.sort = editing.value.sort ?? 0
  try {
    await api(`${screen.value.path}${editing.value ? `/${editing.value.id}` : ''}`, { method: editing.value ? 'PATCH' : 'POST', body: JSON.stringify(payload) })
    closeModal(); await loadScreen()
  } catch (cause) { operationError.value = cause.message }
  finally { saving.value = false }
}
function openAssignment(row, kind) {
  editing.value = row; modal.value = kind; operationError.value = ''
  if (kind === 'rolePermissions') selected.value = permissions.value.filter(item => row.permission_keys?.includes(item.perm_key)).map(item => item.id)
  if (kind === 'rolePermissions') expandedModules.value = permissionGroups.value.map(group => group.name)
  if (kind === 'userRoles') selected.value = roles.value.filter(item => row.role_codes?.includes(item.role_code)).map(item => item.id)
  if (kind === 'departmentShops') selected.value = [...(row.shop_ids || [])]
}
function allInModuleSelected(group) { return group.items.every(item => selected.value.includes(item.id)) }
function toggleModulePermissions(group) {
  if (allInModuleSelected(group)) selected.value = selected.value.filter(id => !group.items.some(item => item.id === id))
  else selected.value = [...new Set([...selected.value, ...group.items.map(item => item.id)])]
}
function toggleModuleOpen(name) {
  expandedModules.value = expandedModules.value.includes(name) ? expandedModules.value.filter(item => item !== name) : [...expandedModules.value, name]
}
const assignmentOptions = computed(() => modal.value === 'rolePermissions' ? permissions.value.map(item => ({ id: item.id, label: `${item.perm_name} · ${item.perm_key}`, hint: item.description })) : modal.value === 'userRoles' ? roles.value.map(item => ({ id: item.id, label: `${item.role_name} · ${item.role_code}`, hint: item.description })) : shops.value.map(item => ({ id: item.id, label: `${item.shop_name} · ${item.platform}`, hint: `${item.shop_code} · 分管部门：${(item.dept_names || []).join('、') || '未分配'}` })))
const assignmentTitle = computed(() => ({ rolePermissions: '分配角色权限', userRoles: '分配角色', departmentShops: '店铺分配', confirmDelete: '提示', confirmReset: '提示', passwordResult: '重置密码成功' })[modal.value] || '')
async function saveAssignment() {
  saving.value = true; operationError.value = ''
  const route = modal.value === 'rolePermissions' ? `/rbac/roles/${editing.value.id}/permissions` : modal.value === 'userRoles' ? `/rbac/users/${editing.value.id}/roles` : `/rbac/departments/${editing.value.id}/shops`
  const payload = modal.value === 'rolePermissions' ? { permission_ids: selected.value.map(Number) } : { ids: selected.value.map(Number) }
  try { await api(route, { method: 'PUT', body: JSON.stringify(payload) }); closeModal(); await loadScreen() }
  catch (cause) { operationError.value = cause.message }
  finally { saving.value = false }
}
async function deleteDepartment(row) {
  if (!confirm(`确定删除部门「${row.dept_name}」？`)) return
  try { await api(`/rbac/departments/${row.id}`, { method: 'DELETE' }); await loadScreen() }
  catch (cause) { error.value = cause.message }
}
function openUserAction(row, kind) {
  editing.value = row
  operationError.value = ''
  temporaryPassword.value = ''
  modal.value = kind
}
function generatePassword() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#$%'
  const random = crypto.getRandomValues(new Uint8Array(16))
  return Array.from(random, byte => chars[byte % chars.length]).join('')
}
async function confirmUserAction() {
  saving.value = true; operationError.value = ''
  try {
    if (modal.value === 'confirmReset') {
      const password = generatePassword()
      await api(`/rbac/users/${editing.value.id}/reset-password`, { method: 'POST', body: JSON.stringify({ password }) })
      temporaryPassword.value = password
      modal.value = 'passwordResult'
    } else if (modal.value === 'confirmDelete') {
      await api(`/rbac/${screenKey.value === 'roles' ? 'roles' : 'users'}/${editing.value.id}`, { method: 'DELETE' })
      closeModal()
      await loadScreen()
    }
  } catch (cause) { operationError.value = cause.message }
  finally { saving.value = false }
}
onMounted(async () => { if (token.value) { try { currentUser.value = await api('/auth/me'); myPermissions.value = await api('/rbac/my-permissions'); if (!canManage.value && myAgentGroups.value.length) screenKey.value = `module:${myAgentGroups.value[0].name}`; if (canManage.value || isModuleScreen.value) await loadScreen() } catch { signOut() } } })
</script>

<template>
  <div v-if="!currentUser" class="login-layout">
    <section class="login-story"><div class="wordmark"><span class="mark">C</span><strong>CrossPilot</strong></div><div class="story-content"><span class="eyebrow">CROSS BORDER OPERATIONS</span><h1>每一项权限，<br>都有清晰边界。</h1><p>一个工作台，管理租户、组织成员、店铺和平台连接。</p><div class="story-features"><span>◈ 多租户隔离</span><span>◇ 角色权限</span><span>⌁ 店铺连接</span></div></div><small>CrossPilot / 管理控制台</small></section>
    <section class="login-side">
      <form v-if="authMode === 'login'" class="login-card" @submit.prevent="signIn">
        <span class="eyebrow">WELCOME BACK</span><h2>登录管理台</h2><p>输入租户编码和账号，继续管理您的工作空间。</p>
        <label>租户编码<input v-model.trim="login.org_code" required autocomplete="organization" placeholder="例如 RBAC_TEST"></label>
        <label>用户名<input v-model.trim="login.username" required autocomplete="username" placeholder="请输入用户名"></label>
        <label>密码<input v-model="login.password" type="password" required autocomplete="current-password" placeholder="请输入密码"></label>
        <div v-if="registrationNotice" class="success-note" role="status">{{ registrationNotice }}</div>
        <div v-if="loginError" class="alert">{{ loginError }}</div>
        <button class="button primary full" type="submit">登录工作台 <span>→</span></button>
        <div class="auth-switch">还没有账号？<button type="button" @click="openRegistration">注册账号</button></div>
      </form>
      <form v-else class="login-card" @submit.prevent="signUp">
        <span class="eyebrow">CREATE ACCOUNT</span><h2>注册账号</h2><p>注册已有租户的账号。管理员启用并分配角色后即可登录。</p>
        <label>租户编码<input v-model.trim="registerForm.org_code" required autocomplete="organization" placeholder="请输入租户编码"></label>
        <label>用户名<input v-model.trim="registerForm.username" required maxlength="64" autocomplete="username" placeholder="请输入用户名"></label>
        <label>真实姓名<input v-model.trim="registerForm.real_name" required maxlength="64" autocomplete="name" placeholder="请输入真实姓名"></label>
        <label>邮箱<input v-model.trim="registerForm.email" type="email" maxlength="128" autocomplete="email" placeholder="选填"></label>
        <label>手机号<input v-model.trim="registerForm.phone" type="tel" maxlength="32" autocomplete="tel" placeholder="选填"></label>
        <label>密码<input v-model="registerForm.password" type="password" required minlength="8" maxlength="128" autocomplete="new-password" placeholder="至少 8 位"></label>
        <label>确认密码<input v-model="registerForm.confirm_password" type="password" required minlength="8" maxlength="128" autocomplete="new-password" placeholder="再次输入密码"></label>
        <div v-if="registrationError" class="alert" role="alert">{{ registrationError }}</div>
        <button class="button primary full" type="submit" :disabled="registering">{{ registering ? '提交中…' : '提交注册' }} <span>→</span></button>
        <div class="auth-switch">已有账号？<button type="button" @click="returnToLogin">返回登录</button></div>
      </form>
    </section>
  </div>
  <div v-else class="layout">
    <aside class="sidebar"><div class="wordmark"><span class="mark">C</span><div><strong>CrossPilot</strong><small>运营管理台</small></div></div><div class="workspace-label">工作空间 <span>#{{ currentUser.org_id }}</span></div><nav aria-label="功能分类"><section v-for="group in visibleGroups" :key="group.name" class="nav-group"><div class="group-label">{{ group.name }}</div><button v-for="item in group.items" :key="item.key" type="button" :class="['nav-link', { active: screenKey === item.key }]" @click="navigate(item.key)"><span class="nav-icon">{{ item.icon }}</span>{{ item.title }}</button></section></nav><div class="sidebar-foot"><span class="online-dot"></span>服务已连接</div></aside>
    <div class="main-shell"><header class="topbar"><div class="breadcrumb">管理控制台 <span>/</span> <template v-if="canManage || isModuleScreen">{{ screen.group }} <span>/</span> <strong>{{ screen.title }}</strong></template><strong v-else>暂无可访问功能</strong></div><div class="identity"><span class="user-avatar">{{ currentUser.username.slice(0, 1).toUpperCase() }}</span><span>{{ currentUser.username }}</span><button type="button" class="text-button" @click="signOut">退出</button></div></header><main v-if="canManage || isModuleScreen" class="page"><div class="page-heading"><div><span class="eyebrow">{{ screen.group === '平台配置' ? 'PLATFORM CONFIGURATION' : screen.group === '用户管理' ? 'IDENTITY & ACCESS' : screen.group === 'Agent 模块' ? 'AGENT PERMISSIONS' : 'ORG MANAGEMENT' }}</span><h1>{{ screen.title }}</h1><p>{{ screen.intro }}</p></div><button v-if="!screen.readOnly" class="button primary" type="button" @click="openEditor()">＋ 新增{{ entityLabel }}</button></div>
      <div class="stats"><div class="stat-card"><span>当前记录</span><strong>{{ rows.length }}</strong><small>当前页面的有效数据</small></div><div class="stat-card"><span>租户边界</span><strong class="cyan">#{{ currentUser.org_id }}</strong><small>查询自动按租户过滤</small></div><div class="stat-card"><span>访问控制</span><strong class="purple">{{ currentUser.roles.includes('SUPER_ADMIN') ? '超级管理员' : '角色授权' }}</strong><small>权限在服务端实时校验</small></div></div>
      <section class="content-card">
        <div class="card-head"><div><span class="eyebrow">{{ screen.group }}</span><h2>{{ screen.title }}</h2></div><div v-if="screenKey !== 'users'" class="tools"><input v-model="search" type="search" aria-label="搜索列表" placeholder="搜索当前列表…"><button class="button secondary" type="button" @click="loadScreen">刷新</button></div></div>
        <form v-if="screenKey === 'users'" class="user-filters" role="search" @submit.prevent="applyUserFilters">
          <label for="user-keyword">关键词</label><input id="user-keyword" v-model="userKeyword" type="search" placeholder="用户名/姓名/邮箱" autocomplete="off">
          <label for="user-status">状态</label><select id="user-status" v-model="userStatus"><option value="">全部</option><option value="ENABLED">启用</option><option value="DISABLED">停用</option></select>
          <button class="button primary" type="submit">⌕ 搜索</button><button class="button secondary" type="button" @click="resetUserFilters">↺ 重置</button>
        </form>
        <div v-if="error" class="alert">{{ error }}</div>
        <div v-if="loading" class="empty">正在加载…</div>
        <div v-if="!loading && screenKey === 'permissions'" class="permission-catalog"><section v-for="group in catalogGroups" :key="group.name" class="catalog-module"><h3>{{ group.name }} <small>{{ group.items.length }} 项权限</small></h3><div v-for="item in group.items" :key="item.id" class="catalog-permission"><strong>{{ item.perm_name }}</strong><code>{{ item.perm_key }}</code><span>{{ item.description || '暂无业务说明' }}</span></div></section><div v-if="!catalogGroups.length" class="empty">暂无权限</div></div>
        <div v-else-if="!loading" class="table-scroll"><table><thead><tr><th v-for="[, label] in screen.columns" :key="label">{{ label }}</th><th v-if="!screen.readOnly">操作</th></tr></thead><tbody><tr v-for="row in paginatedRows" :key="row.id"><td v-for="[key] in screen.columns" :key="key" :class="{ 'description-cell': key === 'description' }"><span v-if="key === 'status'" class="status-pill">{{ display(row, key) }}</span><span v-else :title="display(row, key)">{{ display(row, key) }}</span></td><td v-if="!screen.readOnly" class="row-actions"><button type="button" @click="openEditor(row)">编辑</button><button v-if="screenKey === 'users'" type="button" @click="openAssignment(row, 'userRoles')">分配角色</button><button v-if="screenKey === 'users'" type="button" @click="openUserAction(row, 'confirmReset')">重置密码</button><button v-if="screenKey === 'users'" type="button" class="danger-link" @click="openUserAction(row, 'confirmDelete')">删除</button><button v-if="screenKey === 'roles'" type="button" @click="openAssignment(row, 'rolePermissions')">分配权限</button><button v-if="screenKey === 'roles'" type="button" class="danger-link" @click="openUserAction(row, 'confirmDelete')">删除</button><button v-if="screenKey === 'departments'" type="button" @click="openAssignment(row, 'departmentShops')">店铺分配</button><button v-if="screenKey === 'departments'" type="button" class="danger-link" @click="deleteDepartment(row)">删除</button></td></tr><tr v-if="!paginatedRows.length"><td :colspan="screen.columns.length + (screen.readOnly ? 0 : 1)" class="empty">{{ screenKey === 'users' && (appliedUserKeyword || appliedUserStatus) || search ? '没有匹配的记录' : '暂无记录' }}</td></tr></tbody></table></div>
        <div v-if="screenKey === 'users'" class="user-pagination"><span>共 {{ visibleRows.length }} 条</span><label>每页 <select v-model.number="userPageSize" @change="setUserPage(1)"><option :value="10">10</option><option :value="20">20</option><option :value="50">50</option></select> 条</label><button type="button" :disabled="userPage <= 1" aria-label="上一页" @click="setUserPage(userPage - 1)">‹</button><span>{{ userPage }} / {{ userPageCount }}</span><button type="button" :disabled="userPage >= userPageCount" aria-label="下一页" @click="setUserPage(userPage + 1)">›</button><label>跳至 <input :value="userPage" type="number" min="1" :max="userPageCount" aria-label="跳转页码" @change="setUserPage($event.target.value)"> 页</label></div>
        <div v-else class="table-foot">显示 {{ visibleRows.length }} / {{ rows.length }} 条记录</div>
      </section>
    </main><main v-else class="page"><section class="no-access"><span class="eyebrow">ACCESS REQUIRED</span><h1>暂无可访问功能</h1><p>当前账号没有已授权的模块权限。请联系租户管理员分配角色后重新登录。</p></section></main></div>
  </div>

  <div v-if="modal" class="modal-backdrop" @click.self="closeModal">
    <div class="modal" role="dialog" aria-modal="true" :aria-label="modal === 'editor' ? `${editing ? '编辑' : '新增'}${entityLabel}` : assignmentTitle">
      <header><div><span class="eyebrow">{{ modal === 'editor' ? editing ? 'EDIT RECORD' : 'CREATE RECORD' : 'ACCESS MANAGEMENT' }}</span><h2>{{ modal === 'editor' ? `${editing ? '编辑' : '新增'}${entityLabel}` : assignmentTitle }}</h2></div><button class="close-button" type="button" aria-label="关闭" @click="closeModal">×</button></header>
      <form v-if="modal === 'editor'" @submit.prevent="saveEditor">
        <div class="field-grid"><label v-for="[key, label, type, required] in screen.fields" :key="key" :class="{ wide: type === 'textarea' }">{{ label }}<select v-if="type === 'department'" v-model="form[key]"><option value="">无</option><option v-for="dept in departments" :key="dept.id" :value="dept.id">{{ dept.dept_name }} ({{ dept.dept_code }})</option></select><select v-else-if="type === 'manager'" v-model="form[key]"><option value="">待指派</option><option v-for="manager in managerCandidates" :key="manager.id" :value="manager.id">{{ manager.real_name }}（{{ manager.username }}）· {{ manager.dept_name || '未分配部门' }}</option></select><select v-else-if="type === 'parent'" v-model="form[key]"><option :value="0">根节点 (0)</option><option v-for="dept in departments.filter(item => item.id !== editing?.id)" :key="dept.id" :value="dept.id">{{ dept.dept_name }}</option></select><select v-else-if="type === 'shop'" v-model="form[key]" :required="required"><option value="">请选择店铺</option><option v-for="shop in shops" :key="shop.id" :value="shop.id">{{ shop.shop_name }}</option></select><select v-else-if="type === 'status'" v-model="form[key]"><option>ENABLED</option><option>DISABLED</option></select><select v-else-if="type === 'orgStatus'" v-model="form[key]"><option>ACTIVE</option><option>PENDING</option><option>SUSPENDED</option><option>EXPIRED</option></select><select v-else-if="type === 'scope'" v-model="form[key]"><option>SELF</option><option>DEPT</option><option>DEPT_AND_CHILDREN</option><option>ORG</option><option>ALL</option></select><textarea v-else-if="type === 'textarea'" v-model="form[key]" rows="3" :placeholder="`请输入${label}`"></textarea><input v-else v-model="form[key]" :type="type" :required="required && !(editing && type === 'password')" :min="type === 'number' ? 0 : undefined" :placeholder="editing && type === 'password' ? '留空则保持原凭据' : `请输入${label}`" :disabled="editing && screenKey === 'users' && key === 'username'"></label></div>
        <div v-if="operationError" class="alert">{{ operationError }}</div><footer><button class="button secondary" type="button" @click="closeModal">取消</button><button class="button primary" type="submit" :disabled="saving">{{ saving ? '保存中…' : '保存' }}</button></footer>
      </form>
      <div v-else-if="modal === 'rolePermissions'">
        <div class="permission-groups"><section v-for="group in permissionGroups" :key="group.name" class="permission-module"><div class="permission-module-head"><button type="button" class="module-expand" :aria-label="`展开${group.name}`" @click="toggleModuleOpen(group.name)">{{ expandedModules.includes(group.name) ? '▾' : '▸' }}</button><label><input type="checkbox" :checked="allInModuleSelected(group)" @change="toggleModulePermissions(group)"><strong>{{ group.name }}</strong><small>{{ group.items.filter(item => selected.includes(item.id)).length }} / {{ group.items.length }}</small></label></div><div v-if="expandedModules.includes(group.name)" class="module-permissions"><label v-for="item in group.items" :key="item.id" class="assignment-option"><input v-model="selected" type="checkbox" :value="item.id"><span><strong>{{ item.perm_name }}</strong><small>{{ item.perm_key }} · {{ item.description }}</small></span></label></div></section></div>
        <div v-if="operationError" class="alert">{{ operationError }}</div><footer><button class="button secondary" type="button" @click="closeModal">取消</button><button class="button primary" type="button" :disabled="saving" @click="saveAssignment">{{ saving ? '保存中…' : '保存授权' }}</button></footer>
      </div>
      <div v-else-if="['userRoles', 'departmentShops'].includes(modal)">
        <div class="assignment-list"><label v-for="option in assignmentOptions" :key="option.id" class="assignment-option"><input v-model="selected" type="checkbox" :value="option.id"><span><strong>{{ option.label }}</strong><small>{{ option.hint }}</small></span></label></div>
        <div v-if="operationError" class="alert">{{ operationError }}</div><footer><button class="button secondary" type="button" @click="closeModal">取消</button><button class="button primary" type="button" :disabled="saving" @click="saveAssignment">{{ saving ? '保存中…' : '保存授权' }}</button></footer>
      </div>
      <div v-else class="confirm-body">
        <p v-if="modal === 'confirmDelete'">确定删除{{ screenKey === 'roles' ? '角色' : '用户' }}「{{ screenKey === 'roles' ? editing?.role_name : editing?.username }}」吗？</p>
        <p v-else-if="modal === 'confirmReset'">确定重置用户「{{ editing?.username }}」的密码吗？系统将生成临时密码。</p>
        <div v-else><p>请立即复制并安全交付给用户。关闭弹窗后将无法再次查看。</p><output class="temporary-password">{{ temporaryPassword }}</output></div>
        <div v-if="operationError" class="alert">{{ operationError }}</div>
        <footer><button v-if="modal !== 'passwordResult'" class="button secondary" type="button" @click="closeModal">取消</button><button class="button primary" type="button" :disabled="saving" @click="modal === 'passwordResult' ? closeModal() : confirmUserAction()">{{ modal === 'passwordResult' ? '完成' : saving ? '处理中…' : '确定' }}</button></footer>
      </div>
    </div>
  </div>
</template>
