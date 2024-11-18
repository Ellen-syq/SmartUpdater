
from solidity_parser import parser
import gurobipy as gp
from gurobipy import GRB

def analyze_contract(input_file):

    with open(input_file, 'r') as f:
        content = f.read()

    ast = parser.parse(content)

    contracts = {}
    for node in ast['children']:
        if node['type'] == 'ContractDefinition':
            contracts[node['name']] = node

    if not contracts:
        print("No contract definition found.")
        return

    original_contract_name = list(contracts.keys())[0]
    contract_ast = contracts[original_contract_name]

    state_vars = []
    for item in contract_ast['subNodes']:
        if item['type'] == 'StateVariableDeclaration':
            state_vars.append(item)

    state_var_indices = {var['variables'][0]['name']: idx for idx, var in enumerate(state_vars)}

    T = [get_type_description(var['variables'][0]['typeName']) for var in state_vars]


    S = []

    functions = []
    for item in contract_ast['subNodes']:
        if item['type'] == 'FunctionDefinition':
            functions.append(item)


    for func in functions:

        func_state_usage = [0] * len(state_vars)

        if func.get('body'):
            collect_state_usage(func['body'], state_var_indices, func_state_usage)
        S.append(func_state_usage)

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
    C = []

    for var in state_vars:
        var_name = var['variables'][0]['name']
        if 'initialValue' in var:
            initial_value = var['initialValue']
            references = collect_state_references(initial_value, state_var_indices)
            for ref in references:
                C.append([state_var_indices[var_name] + 1, ref + 1])

    C = [list(x) for x in set(tuple(x) for x in C)]
    return C

def collect_state_references(node, state_var_indices):

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


def optimize_contract(S, T, C,N):  
    min_val = None
    obj_val = None

    M = 100
    M5 = 10000000000000  
    try:
        m = gp.Model("mip1")

        m.Params.OutputFlag = 0

        n_states = len(T)  
        n_funcs = len(S)
        x = m.addVars(n_states, n_funcs, vtype=GRB.BINARY, name="x")  # x[i,j] = 1,说明第i个状态被放在第j个sub-contract中
        y = m.addVars(n_funcs, vtype=GRB.BINARY, name="y")

        h = m.addVars(n_funcs, vtype=GRB.BINARY, name="h")
        h_deploy = m.addVars(n_funcs, vtype=GRB.CONTINUOUS, name="h_d")
        z = m.addVars(n_funcs, vtype=GRB.BINARY, name="z")
        all_deploy = m.addVars(n_funcs,vtype=GRB.CONTINUOUS, name="all_deploy")

        all_in_one = m.addVar(vtype=GRB.BINARY, name="all_in_one")
        Sub_deploy = m.addVar(n_states, vtype=GRB.CONTINUOUS, name="Sub_deploy")
        redeployment = m.addVar(vtype=GRB.CONTINUOUS, name="redeployment")
        migration = m.addVar(vtype=GRB.CONTINUOUS, name="migration")
        num = m.addVar(vtype=GRB.CONTINUOUS, name="num")

        B1 = 66854  
        B_m = 353824 
        B_p = B1 + 256083  
        B2 = 442835  

        D1_dict = {"uint256": 21679, "uint8": 26809, "address": 37578, "bool": 24663, "string": 98739,
                   "mapping": 60465, "int": 21679, "int256": 21679,"uint": 21679}  

        D2_dict = {"uint256": 0, "uint8": 0, "address": 0, "bool": 0, "string": 0, "mapping": 76322, "int": 0,
                   "int256": 0,"uint": 21679,"uint": 21679}

        R_s = {"uint256": 11828, "uint8": 12421, "address": 13537, "bool": 12226, "string": 18545, "mapping": 31818,
               "int": 11828, "int256": 11828,"uint": 21679}

        R_s["mapping"] = N * R_s["mapping"]


        for i in range(len(S)):
            states_in_function = [j for j in range(n_states) if S[i][j] == 1]
            
            all_in_k = m.addVars(n_funcs, vtype=GRB.BINARY, name="all_in_k")
            for k in range(n_funcs):
            
                for j in states_in_function:
                    m.addConstr(x[j, k] >= all_in_k[k], f"c_func_{i}_state_{j}_sub_{k}")

            
                m.addConstr(sum(x[j, k] for j in states_in_function) >= all_in_k[k] * len(states_in_function),
                            f"c_func_{i}_sub_{k}_all_in")

        
            m.addConstr(sum(all_in_k[k] for k in range(n_funcs)) >= 1, f"c_func_{i}_at_least_one_sub")

        for i in range(n_states):
            m.addConstr(sum(x[i, j] for j in range(n_funcs)) == 1, "c1")

        flag = m.addVars(n_funcs, n_states, vtype=GRB.BINARY, name="flag")

        for i in range(n_states):
            for j in range(n_funcs):
                m.addConstr(flag[j, i] >= x[i, j], f"flag1_{j}_{i}")

        for i in range(n_states):
            for j in range(1, n_funcs):  
                m.addConstr(flag[j, i] <= sum(x[t, j - 1] for t in range(n_states)), f"flag2_{j}_{i}")


        for relation in C:
            state1, state2 = relation[0] - 1, relation[1] - 1  
            for j in range(n_funcs):
                m.addConstr(x[state1, j] == x[state2, j], f"c_state_relation_{state1}_{state2}_sub_{j}")

        for j in range(n_funcs):
            m.addConstr((y[j] <= sum(x[i, j] for i in range(n_states))), "c5")
            m.addConstr((sum(x[i, j] for i in range(n_states)) <= y[j] * M), "c6")

        m.addConstr(num == sum(y[j] for j in range(n_funcs)))  

        m.addConstr((1 - all_in_one) <= M * (num - 1), "c7")
        m.addConstr((num - 1) <= M * (1 - all_in_one), "c8")


        m.addConstr(Sub_deploy <= B_m + B1 + sum(D1_dict[T[i]] for i in range(n_states)) + M5 * (1 - all_in_one),
                    "c8")
        m.addConstr(Sub_deploy >= B_m + B1 + sum(D1_dict[T[i]] for i in range(n_states)) - M5 * (1 - all_in_one),
                    "c9")

        m.addConstr(Sub_deploy <= num * B_p + sum(
            x[i, j] * D1_dict[T[i]] for i in range(n_states) for j in range(n_funcs)) + M5 * all_in_one,
                    "c10")
        m.addConstr(Sub_deploy >= num * B_p + sum(
            x[i, j] * D1_dict[T[i]] for i in range(n_states) for j in range(n_funcs)) - M5 * all_in_one,
                    "c11")


        mig = [0]*n_states
        for st in range(n_states):
            mig[st] = sum(x[st, j] * x[index, j] * (D1_dict[T[index]] + D2_dict[T[index]]+R_s[T[index]])  for j in range(n_funcs) for index in range(n_states) if index != st)
        m.addConstr(migration == sum(mig[i] for i in range(n_states)))


        redeploy = [0] * n_states

        for st in range(n_states):
            redeploy[st] = sum(x[st, j] * (B2 + D1_dict[T[st]]) for j in range(n_funcs))
        # m.addConstr(redeployment <= sum(redeploy[i] for i in range(n_states)) + M5 * all_in_one)
        # m.addConstr(redeployment >= sum(redeploy[i] for i in range(n_states)) - M5 * all_in_one)
        m.addConstr(redeployment <= sum(x[i, j] * (B2 + D1_dict[T[i]]) for j in range(n_funcs) for i in range(n_states)) + M5 * all_in_one)
        m.addConstr(redeployment >= sum(x[i, j] * (B2 + D1_dict[T[i]]) for j in range(n_funcs) for i in range(n_states)) - M5 * all_in_one)


        m.addConstr(redeployment <= sum(B_m + B1 + 47292 + D1_dict[T[i]] for i in range(n_states)) + M5 * (1 - all_in_one), "c14_")
        m.addConstr(redeployment >= sum(B_m + B1 + 47292 + D1_dict[T[i]] for i in range(n_states)) - M5 * (1 - all_in_one), "c15_")


        objective = gp.LinExpr()
        objective += Sub_deploy + migration + redeployment

        m.setObjective(objective, GRB.MINIMIZE)
        m.Params.NonConvex = 2

        m.optimize()

        var_names = []

        if m.status == GRB.Status.OPTIMAL:
            for i in range(n_states):
                for j in range(n_funcs):
                    
                    var = x[i, j]
                    if var.X == 1:
                        var_names.append(var.VarName)
                        
            obj_val = m.ObjVal

            Sub_total_value = Sub_deploy.X + redeployment.X + migration.X

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