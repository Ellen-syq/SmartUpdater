
from solidity_parser import parser
import gurobipy as gp
from gurobipy import GRB

def analyze_contract(input_file):
    # 读取 Solidity 文件内容
    with open(input_file, 'r') as f:
        content = f.read()

    # 解析 Solidity 文件
    ast = parser.parse(content)

    # 找到合约定义
    contracts = {}
    for node in ast['children']:
        if node['type'] == 'ContractDefinition':
            contracts[node['name']] = node

    if not contracts:
        print("No contract definition found.")
        return

    # 假设只有一个合约
    original_contract_name = list(contracts.keys())[0]
    contract_ast = contracts[original_contract_name]

    # 收集状态变量
    state_vars = []
    for item in contract_ast['subNodes']:
        if item['type'] == 'StateVariableDeclaration':
            state_vars.append(item)

    # 创建变量名到索引的映射
    state_var_indices = {var['variables'][0]['name']: idx for idx, var in enumerate(state_vars)}

    # 获取每个状态变量的类型
    T = [get_type_description(var['variables'][0]['typeName']) for var in state_vars]

    # 初始化 S：一个列表，表示每个函数中使用的状态变量
    S = []

    # 收集函数
    functions = []
    for item in contract_ast['subNodes']:
        if item['type'] == 'FunctionDefinition':
            functions.append(item)

    # 分析每个函数，查看其使用了哪些状态变量
    for func in functions:
        # 为该函数初始化一个列表，初始值为 0
        func_state_usage = [0] * len(state_vars)
        # 遍历函数体，查找状态变量的使用
        if func.get('body'):
            collect_state_usage(func['body'], state_var_indices, func_state_usage)
        S.append(func_state_usage)

    # 初始化 C（状态变量之间的关系）
    C = detect_state_variable_references(state_vars, state_var_indices)

    return S, T, C

def collect_state_usage(node, state_var_indices, func_state_usage):
    if isinstance(node, dict):
        if node['type'] == 'Identifier' and node['name'] in state_var_indices:
            idx = state_var_indices[node['name']]
            func_state_usage[idx] = 1
        else:
            for key, value in node.items():
                collect_state_usage(value, state_var_indices, func_state_usage)
    elif isinstance(node, list):
        for item in node:
            collect_state_usage(item, state_var_indices, func_state_usage)

def detect_state_variable_references(state_vars, state_var_indices):
    """
    检测状态变量之间是否存在引用。
    如果一个状态变量在声明时引用了其他状态变量，则记录它们之间的关系。
    """
    C = []

    for var in state_vars:
        var_name = var['variables'][0]['name']
        # 获取状态变量的初始值（如果有）
        if 'initialValue' in var:
            initial_value = var['initialValue']
            # 检查初始值中是否引用了其他状态变量
            references = collect_state_references(initial_value, state_var_indices)
            for ref in references:
                # 将变量及其引用的状态变量之间的关系存储到 C 中
                C.append([state_var_indices[var_name] + 1, ref + 1])

    # 去重
    C = [list(x) for x in set(tuple(x) for x in C)]
    return C

def collect_state_references(node, state_var_indices):
    """
    收集一个表达式或初始值中引用的所有状态变量，返回状态变量索引的列表。
    """
    references = []

    if isinstance(node, dict):
        if node['type'] == 'Identifier' and node['name'] in state_var_indices:
            references.append(state_var_indices[node['name']])
        else:
            for key, value in node.items():
                references.extend(collect_state_references(value, state_var_indices))
    elif isinstance(node, list):
        for item in node:
            references.extend(collect_state_references(item, state_var_indices))

    return references


def get_type_description(type_node):
    if type_node['type'] == 'ElementaryTypeName':
        return type_node['name']
    elif type_node['type'] == 'UserDefinedTypeName':
        return type_node['namePath']
    elif type_node['type'] == 'Mapping':
        from_type = get_type_description(type_node['keyType'])
        to_type = get_type_description(type_node['valueType'])
        return 'mapping'
    elif type_node['type'] == 'ArrayTypeName':
        base_type = get_type_description(type_node['baseTypeName'])
        length = type_node.get('length')
        if length:
            return '{}[{}]'.format(base_type, length['value'])
        else:
            return '{}[]'.format(base_type)
    else:
        return 'unknown'


def optimize_contract(S, T, C,N):  # S[]表示第几个函数中有哪些状态； T[]表示有哪些类型的状态；C[]状态之间的关系 ; NUM[] 表示这些状态的量级（在实验中表示array、mapping的量级，同一个值）
    min_val = None
    obj_val = None

    M = 100
    M5 = 10000000000000  # this should be a large enough value, greater than the maximum possible value of Sub_total
    try:
        m = gp.Model("mip1")

        # 禁用Gurobi的输出日志
        m.Params.OutputFlag = 0

        n_states = len(T)  # 状态个数
        n_funcs = len(S)
        x = m.addVars(n_states, n_funcs, vtype=GRB.BINARY, name="x")  # x[i,j] = 1,说明第i个状态被放在第j个sub-contract中
        y = m.addVars(n_funcs, vtype=GRB.BINARY, name="y")

        h = m.addVars(n_funcs, vtype=GRB.BINARY, name="h")
        h_deploy = m.addVars(n_funcs, vtype=GRB.CONTINUOUS, name="h_d")
        z = m.addVars(n_funcs, vtype=GRB.BINARY, name="z")
        all_deploy = m.addVars(n_funcs,vtype=GRB.CONTINUOUS, name="all_deploy")

        all_in_one = m.addVar(vtype=GRB.BINARY, name="all_in_one")
        Sub_deploy = m.addVar(n_states, vtype=GRB.CONTINUOUS, name="Sub_deploy")
        #redeploy = m.addVars(n_states,vtype=GRB.CONTINUOUS, name="redeploy")
        redeployment = m.addVar(vtype=GRB.CONTINUOUS, name="redeployment")
        #mig = m.addVars(n_states,n_funcs, vtype=GRB.CONTINUOUS, name="mig")
        migration = m.addVar(vtype=GRB.CONTINUOUS, name="migration")
        num = m.addVar(vtype=GRB.CONTINUOUS, name="num")

        # C = [[]]  # C = [[3，4]]表示3和4 state之间是有联系的
        B1 = 66854  # old:部署一个blank contract必要的开销
        B_m = 353824  # 合并为一个state部署时，需要的delegatecall gas
        B_p = B1 + 256083  # 切分后，一个sub-state部署时需要的delegatecall gas
        B2 = 442835  # new合约一定有的部分:old address+ constructor（空的constructor不增加gas）
        # 没有赋值
        D1_dict = {"uint256": 21679, "uint8": 26809, "address": 37578, "bool": 24663, "string": 98739,
                   "mapping": 60465, "int": 21679, "int256": 21679,"uint": 21679}  # 部署每个类型需要增加的gas(包括：声明+get())——放在第一个
        # 新合约中，要为mapping设置set函数，增加的部署开销
        D2_dict = {"uint256": 0, "uint8": 0, "address": 0, "bool": 0, "string": 0, "mapping": 76322, "int": 0,
                   "int256": 0,"uint": 21679,"uint": 21679}
        # 读取每个类型的开销
        R_s = {"uint256": 11828, "uint8": 12421, "address": 13537, "bool": 12226, "string": 18545, "mapping": 31818,
               "int": 11828, "int256": 11828,"uint": 21679}

        R_s["mapping"] = N * R_s["mapping"]


        # # 有调用关系的函数里面的状态放在一起

        # #（1）同一个函数中的两个状态需要放在同一个sub-state中
        # For each function
        for i in range(len(S)):
            # Get the states used in this function
            states_in_function = [j for j in range(n_states) if S[i][j] == 1]
            # For each sub_contract
            # Add a binary variable to indicate if all states in this function are in this sub_contract
            all_in_k = m.addVars(n_funcs, vtype=GRB.BINARY, name="all_in_k")
            for k in range(n_funcs):
                # Constraint: if all_in_k = 1, then all states in this function are in this sub_contract
                for j in states_in_function:
                    m.addConstr(x[j, k] >= all_in_k[k], f"c_func_{i}_state_{j}_sub_{k}")

                # Constraint: if all states in this function are in this sub_contract, then all_in_k = 1
                m.addConstr(sum(x[j, k] for j in states_in_function) >= all_in_k[k] * len(states_in_function),
                            f"c_func_{i}_sub_{k}_all_in")

            # Constraint: for each function, there is at least one sub_contract where all states in this function are
            m.addConstr(sum(all_in_k[k] for k in range(n_funcs)) >= 1, f"c_func_{i}_at_least_one_sub")

        # # (2)每个状态只能在一个子合约中
        for i in range(n_states):
            m.addConstr(sum(x[i, j] for j in range(n_funcs)) == 1, "c1")

        # # (3)（可以没有）继承关系，如果有第i个state sub-contract，则一定有0，1，...i-1
        # 添加一个辅助的二进制变量 flag
        flag = m.addVars(n_funcs, n_states, vtype=GRB.BINARY, name="flag")

        # 如果 x[i, j] = 1, 则 flag[j, i] = 1
        for i in range(n_states):
            for j in range(n_funcs):
                m.addConstr(flag[j, i] >= x[i, j], f"flag1_{j}_{i}")

        # 如果 flag[j, i] = 1, 则必须有一个 t 使得 x[t, j - 1] = 1 (当 j > 0)
        for i in range(n_states):
            for j in range(1, n_funcs):  # 注意这里从 1 开始
                m.addConstr(flag[j, i] <= sum(x[t, j - 1] for t in range(n_states)), f"flag2_{j}_{i}")

        # # (4) 有联系的state在一个sub-state中
        for relation in C:
            state1, state2 = relation[0] - 1, relation[1] - 1  # 将 C 中的状态变量索引转换为 0 开始的索引
            for j in range(n_funcs):
                m.addConstr(x[state1, j] == x[state2, j], f"c_state_relation_{state1}_{state2}_sub_{j}")

        # # 有多少个sub contract
        for j in range(n_funcs):
            m.addConstr((y[j] <= sum(x[i, j] for i in range(n_states))), "c5")
            m.addConstr((sum(x[i, j] for i in range(n_states)) <= y[j] * M), "c6")

        m.addConstr(num == sum(y[j] for j in range(n_funcs)))  # 有状态放入的sub-contract的个数

        # # (6) all_in_one
        # 当 num = 1 时，all_in_one = 1，都放入同一个sub_contract中，相当于没有切分
        # 当 num > 1 时，all_in_one = 0
        m.addConstr((1 - all_in_one) <= M * (num - 1), "c7")
        m.addConstr((num - 1) <= M * (1 - all_in_one), "c8")

        # -------------------Deploy-------------
        # 没有切分的deploy计算
        m.addConstr(Sub_deploy <= B_m + B1 + sum(D1_dict[T[i]] for i in range(n_states)) + M5 * (1 - all_in_one),
                    "c8")
        m.addConstr(Sub_deploy >= B_m + B1 + sum(D1_dict[T[i]] for i in range(n_states)) - M5 * (1 - all_in_one),
                    "c9")
        # 切分后的deploy计算
        m.addConstr(Sub_deploy <= num * B_p + sum(
            x[i, j] * D1_dict[T[i]] for i in range(n_states) for j in range(n_funcs)) + M5 * all_in_one,
                    "c10")
        m.addConstr(Sub_deploy >= num * B_p + sum(
            x[i, j] * D1_dict[T[i]] for i in range(n_states) for j in range(n_funcs)) - M5 * all_in_one,
                    "c11")

        # -------------------Migration-------------

        mig = [0]*n_states
        for st in range(n_states):
            mig[st] = sum(x[st, j] * x[index, j] * (D1_dict[T[index]] + D2_dict[T[index]]+R_s[T[index]])  for j in range(n_funcs) for index in range(n_states) if index != st)
        m.addConstr(migration == sum(mig[i] for i in range(n_states)))


        # # -------------------Redeploy-------------
        redeploy = [0] * n_states
        #redeploy = m.addVars(n_states, vtype=GRB.CONTINUOUS, name="redeploy")
        for st in range(n_states):
            # 切分后的re-deploy计算
            redeploy[st] = sum(x[st, j] * (B2 + D1_dict[T[st]]) for j in range(n_funcs))
        # m.addConstr(redeployment <= sum(redeploy[i] for i in range(n_states)) + M5 * all_in_one)
        # m.addConstr(redeployment >= sum(redeploy[i] for i in range(n_states)) - M5 * all_in_one)
        m.addConstr(redeployment <= sum(x[i, j] * (B2 + D1_dict[T[i]]) for j in range(n_funcs) for i in range(n_states)) + M5 * all_in_one)
        m.addConstr(redeployment >= sum(x[i, j] * (B2 + D1_dict[T[i]]) for j in range(n_funcs) for i in range(n_states)) - M5 * all_in_one)


        # 没有切分的re-deploy计算
        m.addConstr(redeployment <= sum(B_m + B1 + 47292 + D1_dict[T[i]] for i in range(n_states)) + M5 * (1 - all_in_one), "c14_")
        m.addConstr(redeployment >= sum(B_m + B1 + 47292 + D1_dict[T[i]] for i in range(n_states)) - M5 * (1 - all_in_one), "c15_")



        # 目标函数
        objective = gp.LinExpr()
        objective += Sub_deploy + migration + redeployment

        m.setObjective(objective, GRB.MINIMIZE)
        m.Params.NonConvex = 2

        # 解决模型
        m.optimize()

        var_names = []

        if m.status == GRB.Status.OPTIMAL:
            # 遍历所有的x变量
            for i in range(n_states):
                for j in range(n_funcs):
                    # 获取特定的变量
                    var = x[i, j]
                    if var.X == 1:
                        var_names.append(var.VarName)
                        # 打印变量名和值
                        # print('%s %g' % (var.VarName, var.X))
            #print('MIP : %g' % m.ObjVal)
            obj_val = m.ObjVal
            ## ---------------------------------------------------查看每个值(测试)-----------------------------------
            #print('Value of num2: ', num.X)
            #print('Value of all_in_one: ', all_in_one.X)
            #print('Sub_deploy_value ', Sub_deploy)
            #redeploy_values = redeploy
            # for i in range(n_states):
            #     print('red:', redeploy[i].getValue())
            # print('redeploy_values: ', redeployment)
            # for i in range(n_states):
            #     print('mig:',mig[i].getValue())
            # print('migration: ', migration)
            Sub_total_value = Sub_deploy.X + redeployment.X + migration.X
            # print('Sub_total_value ', Sub_total_value)

        elif m.status == GRB.Status.INFEASIBLE:
            print('The model is infeasible. Calculating IIS...')
            m.computeIIS()
            m.write('infeasible.ilp')

        else:
            print('The model has not been optimized or no solution was found.')

        return var_names

    except gp.GurobiError as e:
        print('Error code ' + str(e.errno) + ': ' + str(e))
        return None, None