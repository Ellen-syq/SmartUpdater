import sys
import os
import re
import json
import optimization_partition
import solidityVersion
from packaging import version
from solcx import compile_standard, install_solc,get_installed_solc_versions
from solcx.exceptions import SolcNotInstalled

# 提取存储变量、函数、事件、修饰符、结构体、枚举
state_vars = []
mappings = []
functions = []
events = []
modifiers = []
structs = []
enums = []
# 提取 pragma 语句
pragma_statements = []

def split_contract(input_file, logic_contract_name, proxy_contract_name, hyperlayer_contract_name):
    # 读取 Solidity 文件内容
    with open(input_file, 'r') as f:
        content = f.read()

    # 提取 Solidity 版本号并安装对应的 solc 版本
    try:
        solc_version = extract_solidity_version(content)
        install_solc_version(solc_version)
    except Exception as e:
        print(f"Error installing solc version: {e}")
        sys.exit(1)

    try:
        # 使用 solcx 编译代码并获取 AST
        compiled_sol = compile_standard({
            "language": "Solidity",
            "sources": {
                "Contract.sol": {
                    "content": content
                }
            },
            "settings": {
                "outputSelection": {
                    "*": {
                        "*": [
                            "ast",
                            "evm.bytecode",
                            "abi"
                        ]
                    }
                }
            }
        }, solc_version=solc_version)
    except Exception as e:
        print(f"Error compiling the Solidity contract: {e}")
        sys.exit(1)

    # 获取 AST
    # print("1111111111111111111:")
    # print(compiled_sol['sources']['Contract.sol'])
    ast = solidityVersion.parse_solidity_code_with_solc(content)


    # 找到合约定义
    contracts = {}
    for node in ast['nodes']:
        if node['nodeType'] == 'ContractDefinition':
            contracts[node['name']] = node

    if not contracts:
        print("No contract definition found.")
        return

    # 假设只有一个合约
    original_contract_name = list(contracts.keys())[0]
    contract_ast = contracts[original_contract_name]

    # 遍历合约节点，提取信息
    for item in contract_ast['nodes']:
        if item['nodeType'] == 'VariableDeclaration':
            state_vars.append(item)
            if item['typeName']['nodeType'] == 'Mapping':
                mappings.append(item['name'])
        elif item['nodeType'] == 'FunctionDefinition':
            functions.append(item)
        elif item['nodeType'] == 'EventDefinition':
            events.append(item)
        elif item['nodeType'] == 'ModifierDefinition':
            modifiers.append(item)
        elif item['nodeType'] == 'StructDefinition':
            structs.append(item)
        elif item['nodeType'] == 'EnumDefinition':
            enums.append(item)

    # 收集结构体和枚举的名称集合
    struct_names = set()
    enum_names = set()
    for struct in structs:
        struct_names.add(struct['name'])
    for enum in enums:
        enum_names.add(enum['name'])

    for node in ast['nodes']:
        if node['nodeType'] == 'PragmaDirective':
            # Join literals without extra spaces between version numbers and symbols
            pragma_version = ''.join(node['literals'][1:])
            pragma_statements.append('pragma {} {};'.format(node['literals'][0], pragma_version))

    pragma_code = '\n'.join(pragma_statements) + '\n\n'

    # print("pragma_code_______________________")
    # print(pragma_code)


    solidity_version_str = get_solidity_version(pragma_statements)
    is_solidity_0_6_or_above = version_compare(solidity_version_str, '0.6.0')

    # 使用新的功能，获取 S、T、C
    S, T, C = optimization_partition.analyze_contract(input_file)
    N = 13

    # print("S:", S)
    # print("T:", T)
    # print("C:", C)

    var_names = optimization_partition.optimize_contract(S, T, C, N)
    # print(var_names)

    partition_generate_contracts(var_names, S, pragma_code, is_solidity_0_6_or_above, logic_contract_name, proxy_contract_name, hyperlayer_contract_name, original_contract_name)

def partition_generate_contracts(var_names, S, pragma_code, is_solidity_0_6_or_above, logic_contract_name, proxy_contract_name, hyperlayer_contract_name, contract_name):
    # 1、解析 var_names，并划分状态变量
    # 解析 var_names，构建状态变量到子状态合约的映射
    var_partition = {}  # key: 状态变量索引，value: 子状态合约索引
    for var_name in var_names:
        match = re.match(r'x\[(\d+),(\d+)\]', var_name)
        if match:
            var_idx = int(match.group(1))
            sub_state_idx = int(match.group(2))
            var_partition[var_idx] = sub_state_idx
        else:
            print(f"Invalid var_name format: {var_name}")

    # 构建子状态合约的状态变量列表
    sub_state_vars = {}  # key: 子状态合约索引，value: 状态变量列表
    for var_idx, sub_state_idx in var_partition.items():
        var = state_vars[var_idx]
        if sub_state_idx not in sub_state_vars:
            sub_state_vars[sub_state_idx] = []
        sub_state_vars[sub_state_idx].append(var)

    # 收集 definitions 的依赖关系
    definitions_dependencies = collect_definitions_dependencies()

    # 根据状态变量的划分，将 definitions 分配到子逻辑合约
    sub_logic_definitions = partition_definitions(definitions_dependencies, var_partition)

    # 2、根据 S 划分函数
    # 构建函数对状态变量的使用情况
    function_var_usage = []  # 列表，每个元素是函数使用的状态变量索引集合
    for func_usage in S:
        var_indices = set()
        for var_idx, usage in enumerate(func_usage):
            if usage == 1:
                var_indices.add(var_idx)
        function_var_usage.append(var_indices)
    # 确定每个函数所涉及的子状态合约
    function_sub_state_contracts = []
    for var_indices in function_var_usage:
        sub_state_indices = set()
        for var_idx in var_indices:
            sub_state_idx = var_partition.get(var_idx)
            if sub_state_idx is not None:
                sub_state_indices.add(sub_state_idx)
        function_sub_state_contracts.append(sub_state_indices)

    # 收集每个函数的依赖项
    function_dependencies = []  # 每个函数的依赖项，包括事件、修饰符、结构体、枚举

    for func in functions:
        deps = {
            'events': set(),
            'modifiers': set(),
            'structs': set(),
            'enums': set()
        }
        # 收集修饰符
        if 'modifiers' in func and func['modifiers']:
            for modifier in func['modifiers']:
                deps['modifiers'].add(modifier['modifierName']['name'])
        # 收集函数体中的事件、结构体、枚举
        if func.get('body'):
            collect_function_dependencies(func['body'], deps)
        function_dependencies.append(deps)

    # 将函数及其依赖项分配到子逻辑合约
    sub_logic_functions = {}  # key: 子状态合约索引，value: (函数列表, 依赖项集合)
    other_functions = []  # 涉及多个子状态合约的函数

    for func_idx, sub_state_indices in enumerate(function_sub_state_contracts):
        deps = function_dependencies[func_idx]
        if len(sub_state_indices) == 1:
            sub_state_idx = next(iter(sub_state_indices))
            if sub_state_idx not in sub_logic_functions:
                sub_logic_functions[sub_state_idx] = (
                [], {'events': set(), 'modifiers': set(), 'structs': set(), 'enums': set()})
            sub_logic_functions[sub_state_idx][0].append(functions[func_idx])
            # 合并依赖项
            for key in deps:
                sub_logic_functions[sub_state_idx][1][key].update(deps[key])
        else:
            # 涉及多个子状态合约的函数
            other_functions.append(functions[func_idx])

    # 生成子状态合约
    for sub_state_idx, vars_in_contract in sub_state_vars.items():
        generate_state_contract(sub_state_idx, vars_in_contract, pragma_code, is_solidity_0_6_or_above, proxy_contract_name)

    # 生成子逻辑合约
    for sub_state_idx, (funcs_in_contract, deps) in sub_logic_functions.items():
        vars_in_contract = sub_state_vars[sub_state_idx]
        # 添加 definitions
        definitions = sub_logic_definitions.get(sub_state_idx,
                                                {'events': set(), 'modifiers': set(), 'structs': set(), 'enums': set()})
        # 合并函数依赖的 definitions
        for key in definitions:
            definitions[key].update(deps[key])
        generate_logic_contract(sub_state_idx, funcs_in_contract, vars_in_contract, pragma_code, definitions, logic_contract_name)

    # 生成 Hyperlayer
    generate_hyperlayer_contract(pragma_code, is_solidity_0_6_or_above, hyperlayer_contract_name)

    # 在 partition_generate_contracts 函数的最后添加
    save_sub_state_vars_info(sub_state_vars, contract_name)
    generate_var_types_json(contract_name)
    save_mappings(var_partition, function_sub_state_contracts, contract_name)

def save_mappings(var_partition, function_sub_state_contracts, contract_name):
    # Save state variable to sub-state contract mapping
    var_mapping = {}
    for var_idx, sub_state_idx in var_partition.items():
        var_name = state_vars[var_idx]['name']
        var_mapping[var_name] = sub_state_idx

    with open(f"{contract_name}_var_mapping.json", 'w') as f:
        json.dump(var_mapping, f)

    # Save function to sub-logic contract mapping
    func_mapping = {}
    for func_idx, sub_state_indices in enumerate(function_sub_state_contracts):
        func_name = functions[func_idx]['name']
        func_mapping[func_name] = list(sub_state_indices)

    with open(f"{contract_name}_func_mapping.json", 'w') as f:
        json.dump(func_mapping, f)

def collect_function_dependencies(node, deps):
    if isinstance(node, dict):
        node_type = node.get('nodeType')
        if node_type == 'EmitStatement':
            event_name = node['eventCall']['expression']['name']
            deps['events'].add(event_name)
        elif node_type == 'VariableDeclarationStatement':
            var_type = node['declarations'][0]['typeName']
            if var_type['nodeType'] == 'UserDefinedTypeName':
                type_name = var_type['namePath']
                # if type_name in struct_names:
                #     deps['structs'].add(type_name)
                # elif type_name in enum_names:
                #     deps['enums'].add(type_name)
        # 递归遍历子节点
        for key, value in node.items():
            if isinstance(value, dict) or isinstance(value, list):
                collect_function_dependencies(value, deps)
    elif isinstance(node, list):
        for item in node:
            collect_function_dependencies(item, deps)

def collect_definitions_dependencies():
    # 创建状态变量名到索引的映射
    state_var_indices = {var['name']: idx for idx, var in enumerate(state_vars)}

    # 定义存储依赖关系的字典
    definitions_dependencies = {
        'events': {},    # key: event name, value: set of state variable indices
        'modifiers': {},
        'structs': {},
        'enums': {}
    }

    # 分析 events
    for event in events:
        deps = set()
        for param in event['parameters']['parameters']:
            collect_type_dependencies(param['typeName'], deps, state_var_indices)
        definitions_dependencies['events'][event['name']] = deps

    # 分析 modifiers
    for modifier in modifiers:
        deps = set()
        if modifier.get('body'):
            collect_node_dependencies(modifier['body'], deps, state_var_indices)
        definitions_dependencies['modifiers'][modifier['name']] = deps

    # 分析 structs
    for struct in structs:
        deps = set()
        for member in struct['members']:
            collect_type_dependencies(member['typeName'], deps, state_var_indices)
        definitions_dependencies['structs'][struct['name']] = deps

    # 分析 enums（通常不涉及状态变量，但为了完整性）
    for enum in enums:
        definitions_dependencies['enums'][enum['name']] = set()

    return definitions_dependencies

def collect_type_dependencies(type_node, deps, state_var_indices):
    if type_node['nodeType'] == 'UserDefinedTypeName':
        type_name = type_node['namePath']
        if type_name in state_var_indices:
            deps.add(state_var_indices[type_name])
    elif type_node['nodeType'] == 'Mapping':
        collect_type_dependencies(type_node['keyType'], deps, state_var_indices)
        collect_type_dependencies(type_node['valueType'], deps, state_var_indices)
    elif type_node['nodeType'] == 'ArrayTypeName':
        collect_type_dependencies(type_node['baseType'], deps, state_var_indices)

def collect_node_dependencies(node, deps, state_var_indices):
    if isinstance(node, dict):
        if node['nodeType'] == 'Identifier':
            name = node['name']
            if name in state_var_indices:
                deps.add(state_var_indices[name])
        else:
            for key, value in node.items():
                if isinstance(value, dict) or isinstance(value, list):
                    collect_node_dependencies(value, deps, state_var_indices)
    elif isinstance(node, list):
        for item in node:
            collect_node_dependencies(item, deps, state_var_indices)

def partition_definitions(definitions_dependencies, var_partition):
    sub_logic_definitions = {}  # key: 子状态合约索引，value: definitions 列表

    for def_type in definitions_dependencies:
        for def_name, deps in definitions_dependencies[def_type].items():
            # 找到这些依赖的状态变量所属的子状态合约
            sub_state_indices = set()
            for var_idx in deps:
                sub_state_idx = var_partition.get(var_idx)
                if sub_state_idx is not None:
                    sub_state_indices.add(sub_state_idx)
            # 将定义添加到对应的子逻辑合约中
            for sub_state_idx in sub_state_indices:
                if sub_state_idx not in sub_logic_definitions:
                    sub_logic_definitions[sub_state_idx] = {'events': set(), 'modifiers': set(), 'structs': set(), 'enums': set()}
                sub_logic_definitions[sub_state_idx][def_type].add(def_name)
    return sub_logic_definitions

def save_sub_state_vars_info(sub_state_vars, contract_name):
    # 将子状态合约的信息保存到文件中，供 maintence.py 使用
    info = {}
    for sub_state_idx, vars_in_contract in sub_state_vars.items():
        var_names = [var['name'] for var in vars_in_contract]
        info[sub_state_idx] = var_names

    with open(f"{contract_name}_sub_state_vars_old.json", 'w') as f:
        json.dump(info, f)

def generate_var_types_json(contract_name):
    var_types = {}
    for var in state_vars:
        var_name = var['name']
        var_type = get_type_description(var['typeName'])
        var_types[var_name] = var_type

    # 将变量类型信息保存到 JSON 文件
    with open(f"{contract_name}_var_types.json", 'w') as f:
        json.dump(var_types, f, indent=4)
    print(f"Generated '{contract_name}_var_types.json'")

def generate_logic_contract(sub_state_idx, functions, state_vars, pragma_code, definitions, logic_contract_name):
    contract_name = f"{logic_contract_name}{sub_state_idx}"  # 例如：MyContractLogic0

    # 构建逻辑合约
    logic_contract = pragma_code
    logic_contract += 'contract ' + contract_name + ' {\n'

    logic_contract += '    address public logicContract; // 占位符，与代理合约存储布局对齐\n'

    for var in state_vars:
        var_code = get_var_declaration(var)
        logic_contract += '    ' + var_code + '\n'

    for var in state_vars:
        var_name = var['name']
        if var_name in mappings:
            # print("var-------------------")
            # print(var_name)
            # print(var['typeName']['keyType']['name'])
            event_code = f"    event {var_name}Event (string contractname, {var['typeName']['keyType']['name']} key);\n"
            logic_contract += event_code

    # 为私有状态变量生成 getter 函数
    for var in state_vars:
        if var.get('visibility') == 'private':
            getter_code = generate_getter_function(var)
            logic_contract += getter_code + '\n'

    # 添加事件
    if definitions['events']:
        logic_contract += '\n    // 事件\n'
        for event in events:
            if event['name'] in definitions['events']:
                event_code = get_event_declaration(event)
                logic_contract += '    ' + event_code + '\n'

    # 添加修饰符
    if definitions['modifiers']:
        logic_contract += '\n    // 修饰符\n'
        for modifier in modifiers:
            if modifier['name'] in definitions['modifiers']:
                modifier_code = get_modifier_declaration(modifier)
                logic_contract += '    ' + modifier_code + '\n'

    # 添加结构体
    if definitions['structs']:
        logic_contract += '\n    // 结构体\n'
        for struct in structs:
            if struct['name'] in definitions['structs']:
                struct_code = get_struct_declaration(struct)
                logic_contract += '    ' + struct_code + '\n'

    # 添加枚举
    if definitions['enums']:
        logic_contract += '\n    // 枚举\n'
        for enum in enums:
            if enum['name'] in definitions['enums']:
                enum_code = get_enum_declaration(enum)
                logic_contract += '    ' + enum_code + '\n'

    # 添加函数
    for func in functions:
        func_code = get_function_definition(func)
        logic_contract += func_code + '\n'

    logic_contract += '}\n'

    # 写入输出文件
    with open(contract_name + '.sol', 'w') as f:
        f.write(logic_contract)

    print('Sub-logic contract is written to ' + contract_name + '.sol')

def generate_getter_function(var):
    var_type = get_type_description(var['typeName'])
    var_name = var['name']
    function_name = f'get_{var_name}'

    # 如果是映射类型，生成带键参数的 getter 函数
    if var_type.startswith('mapping'):
        key_type = get_mapping_key_type(var['typeName'])
        value_type = get_mapping_value_type(var['typeName'])
        function_code = f'    function {function_name}({key_type} key) public view returns ({value_type}) {{\n'
        function_code += f'        return {var_name}[key];\n'
        function_code += '    }\n'
    else:
        # 非映射类型的变量
        function_code = f'    function {function_name}() public view returns ({var_type}) {{\n'
        function_code += f'        return {var_name};\n'
        function_code += '    }\n'

    return function_code

def get_mapping_key_type(type_node):
    if type_node['nodeType'] == 'Mapping':
        return get_type_description(type_node['keyType'])
    return 'unknown'

def get_mapping_value_type(type_node):
    if type_node['nodeType'] == 'Mapping':
        return get_type_description(type_node['valueType'])
    return 'unknown'


def generate_state_contract(sub_state_idx, state_vars, pragma_code, is_solidity_0_6_or_above, proxy_contract_name):
    contract_name = f"{proxy_contract_name}{sub_state_idx}"
    # 构建代理合约
    state_code = pragma_code
    state_code += 'contract ' + contract_name + ' {\n'
    state_code += '    address public logicContract;\n'

    # 添加存储变量，与逻辑合约保持一致
    state_code += '    // 存储变量（必须与逻辑合约一致）\n'
    for var in state_vars:
        var_code = get_var_declaration(var, with_value=True)
        state_code += '    ' + var_code + '\n'

    # 构造函数
    state_code += '\n    // 构造函数\n'
    if is_solidity_0_6_or_above:
        state_code += '    constructor(address _logicContract) public {\n'
    else:
        state_code += f'    function {contract_name}(address _logicContract) public {{\n'
    state_code += '        logicContract = _logicContract;\n'
    state_code += '    }\n'

    # 回退函数
    if is_solidity_0_6_or_above:
        state_code += '\n    // 回退函数\n'
        state_code += '    fallback() external payable {\n'
        state_code += '        address _impl = logicContract;\n'
        state_code += '        require(_impl != address(0));\n\n'
        state_code += '        assembly {\n'
        state_code += '            let ptr := mload(0x40)\n'
        state_code += '            calldatacopy(ptr, 0, calldatasize())\n'
        state_code += '            let result := delegatecall(gas(), _impl, ptr, calldatasize(), 0, 0)\n'
        state_code += '            let size := returndatasize()\n'
        state_code += '            returndatacopy(ptr, 0, size)\n'
        state_code += '            switch result\n'
        state_code += '            case 0 { revert(ptr, size) }\n'
        state_code += '            default { return(ptr, size) }\n'
        state_code += '        }\n'
        state_code += '    }\n'
    else:
        state_code += '\n    // 回退函数\n'
        state_code += '    function () public payable {\n'
        state_code += '        address _impl = logicContract;\n'
        state_code += '        require(_impl != address(0));\n\n'
        state_code += '        assembly {\n'
        state_code += '            let ptr := mload(0x40)\n'
        state_code += '            calldatacopy(ptr, 0, calldatasize())\n'
        state_code += '            let result := delegatecall(gas(), _impl, ptr, calldatasize(), 0, 0)\n'
        state_code += '            let size := returndatasize()\n'
        state_code += '            returndatacopy(ptr, 0, size)\n'
        state_code += '            switch result\n'
        state_code += '            case 0 { revert(ptr, size) }\n'
        state_code += '            default { return(ptr, size) }\n'
        state_code += '        }\n'
        state_code += '    }\n'

    # 升级函数
    state_code += '\n    // 升级函数\n'
    state_code += '    function upgradeTo(address _newLogic) public {\n'
    state_code += '        // 添加访问控制，例如 onlyOwner 修饰符\n'
    state_code += '        logicContract = _newLogic;\n'
    state_code += '    }\n'

    state_code += '}\n'

    with open(contract_name + '.sol', 'w') as f:
        f.write(state_code)

    print('Sub-state contract is written to ' + contract_name + '.sol')

def generate_hyperlayer_contract(pragma_code, is_solidity_0_6_or_above, hyperlayer_contract_name):
    # 构建 Hyperlayer 合约
    hyperlayer_contract = pragma_code
    hyperlayer_contract += 'contract ' + hyperlayer_contract_name + ' {\n'

    # Hyperlayer 中管理逻辑合约地址的映射
    hyperlayer_contract += '    // 状态-逻辑映射，管理状态合约和逻辑合约之间的关系\n'
    hyperlayer_contract += '    mapping(bytes4 => address) public stateLogicMapping;\n'

    # 设置逻辑合约地址的方法
    hyperlayer_contract += '\n    // 设置逻辑合约地址的方法\n'
    hyperlayer_contract += '    function setLogicContract(bytes4 funcSelector, address logicAddress) public {\n'
    hyperlayer_contract += '        stateLogicMapping[funcSelector] = logicAddress;\n'
    hyperlayer_contract += '    }\n'

    # 回退函数，通过 selector 查找合约并使用 call 转发调用
    if is_solidity_0_6_or_above:
        hyperlayer_contract += '\n    // 回退函数\n'
        hyperlayer_contract += '    fallback() external payable {\n'
        hyperlayer_contract += '        address target = stateLogicMapping[msg.sig];\n'
        hyperlayer_contract += '        require(target != address(0), "Logic contract not found");\n'
        hyperlayer_contract += '        (bool success, ) = target.call{value: msg.value}(msg.data);\n'
        hyperlayer_contract += '        require(success, "Call failed");\n'
        hyperlayer_contract += '    }\n'
    else:
        hyperlayer_contract += '\n    // 回退函数\n'
        hyperlayer_contract += '    function () public payable {\n'
        hyperlayer_contract += '        address target = stateLogicMapping[msg.sig];\n'
        hyperlayer_contract += '        require(target != address(0), "Logic contract not found");\n'
        hyperlayer_contract += '        bool success = target.call.value(msg.value)(msg.data);\n'
        hyperlayer_contract += '        require(success, "Call failed");\n'
        hyperlayer_contract += '    }\n'

    hyperlayer_contract += '}\n'

    with open(hyperlayer_contract_name + '.sol', 'w') as f:
        f.write(hyperlayer_contract)

    print('Hyperlayer contract is written to ' + hyperlayer_contract_name + '.sol')

def extract_solidity_version(code):
    """
    提取 Solidity 版本号。
    """
    pragma_regex = r'pragma\s+solidity\s+([^;]+);'
    match = re.search(pragma_regex, code)
    if match:
        version_spec = match.group(1).strip()
        # 提取版本号，例如 '^0.8.0' 或 '>=0.7.0 <0.9.0'
        version_number = version_spec.lstrip('^').split(' ')[0]
        # print(f"Detected Solidity version specification: {version_number}")
        return version_number
    else:
        raise ValueError("Pragma statement not found in the Solidity code.")

def install_solc_version(solc_version):
    installed_versions = get_installed_solc_versions()
    if solc_version not in installed_versions:
        # print(f"Installing solc version {solc_version}...")
        install_solc(solc_version)
    else:
        print(f"solc version {solc_version} is already installed.")

def get_solidity_version(pragma_statements):
    for pragma in pragma_statements:
        if 'solidity' in pragma:
            # 提取版本号，例如 '^0.8.0' 或 '>=0.7.0 <0.9.0'
            version_part = pragma.split('solidity')[1].strip(' ;')
            # 提取主版本号
            import re
            match = re.search(r'(\d+\.\d+\.\d+)', version_part)
            if match:
                return match.group(1)
    return '0.4.21'  # 默认版本

def version_compare(v1, v2):
    from packaging import version
    return version.parse(v1) >= version.parse(v2)

def get_var_declaration(var, with_value=False):
    var_type = get_type_description(var['typeName'])
    var_name = var['name']
    visibility = var.get('visibility', 'public')
    is_constant = 'constant' if var.get('constant', False) else ''

    # 提取初始值（如果有）
    value = ''
    if with_value and 'value' in var and var['value'] is not None:
        value = ' = ' + get_expression_code(var['value'])

    var_code = '{} {} {} {}{}'.format(var_type, visibility, is_constant, var_name, value)
    var_code = ' '.join(var_code.strip().split()) + ';'
    return var_code

def get_type_description(type_node):
    if type_node['nodeType'] == 'ElementaryTypeName':
        return type_node['name']
    elif type_node['nodeType'] == 'UserDefinedTypeName':
        return type_node['namePath']
    elif type_node['nodeType'] == 'Mapping':
        from_type = get_type_description(type_node['keyType'])
        to_type = get_type_description(type_node['valueType'])
        return 'mapping({} => {})'.format(from_type, to_type)
    elif type_node['nodeType'] == 'ArrayTypeName':
        base_type = get_type_description(type_node['baseType'])
        length = type_node.get('length')
        if length:
            return '{}[{}]'.format(base_type, length['number'])
        else:
            return '{}[]'.format(base_type)
    else:
        return 'unknown'

def get_event_declaration(event):
    params = ', '.join(['{} {}{}'.format(
        get_type_description(param['typeName']),
        'indexed ' if param.get('indexed', False) else '',
        param['name']
    ) for param in event['parameters']['parameters']])
    event_code = 'event {}({});'.format(event['name'], params)
    return event_code

def get_modifier_declaration(modifier):
    params = get_parameter_list(modifier.get('parameters'))
    body = get_block_code(modifier['body'])
    modifier_code = 'modifier {}({}) {}'.format(modifier['name'], params, body)
    return modifier_code

def get_struct_declaration(struct):
    members = '\n'.join(['        {} {};'.format(get_type_description(var['typeName']), var['name']) for var in struct['members']])
    struct_code = 'struct {} {{\n{}\n    }}'.format(struct['name'], members)
    return struct_code

def get_enum_declaration(enum):
    members = ', '.join([member['name'] for member in enum['members']])
    enum_code = 'enum {} {{ {} }}'.format(enum['name'], members)
    return enum_code

def get_function_definition(func):
    name = func['name'] if func['name'] else ''
    params = get_parameter_list(func.get('parameters'))
    visibility = func.get('visibility', '')
    is_constructor = func.get('kind') == 'constructor'
    state_mutability = func.get('stateMutability', '')
    returns = get_return_parameters(func.get('returnParameters'))

    body = get_block_code(func['body']) if func.get('body') else ';'

    function_code = '    function {}({}) {} {} {}'.format(
        name,
        params,
        visibility,
        returns,
        body
    )

    # 清理多余的空格
    function_code = ' '.join(function_code.strip().split())

    return function_code

def get_parameter_list(params):
    if not params or not params.get('parameters'):
        return ''
    param_list = []
    for param in params['parameters']:
        param_type = get_type_description(param['typeName'])
        param_name = param.get('name', '')
        if param_name:
            param_list.append(f'{param_type} {param_name}')
        else:
            param_list.append(f'{param_type}')
    return ', '.join(param_list)

def get_return_parameters(returns):
    if not returns or not returns.get('parameters'):
        return ''
    return_params = get_parameter_list(returns)
    return 'returns ({})'.format(return_params)

def get_block_code(block):
    if not block:
        return '{}'
    if block['nodeType'] != 'Block':
        # 如果不是块，则直接获取语句代码
        stmt_code = get_statement_code(block)
        return '{\n' + stmt_code + '\n    }'
    else:
        statements = []
        for stmt in block['statements']:
            stmt_code = get_statement_code(stmt)
            statements.append(stmt_code)
        return '{\n' + '\n'.join(statements) + '\n    }'

def get_statement_code(stmt):
    # 简单处理表达式语句
    # print("stmt---------------------")
    # print(stmt)

    # print(stmt['nodeType'])
    if stmt['nodeType'] == 'ExpressionStatement':
        expr_code = get_expression_code(stmt['expression'])
        # 检查是否是对 mapping 的赋值操作
        if stmt['expression']['nodeType'] == 'Assignment':
            left_expr = stmt['expression']['leftHandSide']
            if left_expr['nodeType'] == 'IndexAccess':
                base_expr = left_expr['baseExpression']
                if base_expr['nodeType'] == 'Identifier' and base_expr['name'] in mappings:
                    key_expr = left_expr['indexExpression']
                    key_code = get_expression_code(key_expr)
                    # print("key_code----------")
                    # print(key_code)
                    mapping_name = base_expr['name']
                    event_emit_code = f'        emit {mapping_name}Event("{mapping_name}", {key_code});'
                    return f'        {expr_code};\n{event_emit_code}'
        return f'        {expr_code};'
    elif stmt['nodeType'] == 'Return':
        expr_code = get_expression_code(stmt['expression']) if stmt.get('expression') else ''
        return f'        return {expr_code};'
    elif stmt['nodeType'] == 'VariableDeclarationStatement':
        declarations = []
        for var in stmt['declarations']:
            if var is not None:
                var_type = get_type_description(var['typeName'])
                var_name = var['name']
                declarations.append(f'{var_type} {var_name}')
            else:
                declarations.append('')
        var_code = ', '.join(declarations)
        expr_code = get_expression_code(stmt['initialValue']) if stmt.get('initialValue') else ''
        if expr_code:
            return f'        {var_code} = {expr_code};'
        else:
            return f'        {var_code};'
    elif stmt['nodeType'] == 'IfStatement':
        condition = get_expression_code(stmt['condition'])
        true_body = get_block_code(stmt['trueBody'])
        false_body = get_block_code(stmt['falseBody']) if stmt.get('falseBody') else ''
        code = f'        if ({condition}) {true_body}\n'
        if false_body:
            code += f'        else {false_body}\n'
        return code
    elif stmt['nodeType'] == 'ForStatement':
        init_stmt = get_statement_code(stmt['initializationExpression']) if stmt.get('initializationExpression') else ''
        condition = get_expression_code(stmt['condition']) if stmt.get('condition') else ''
        loop_expr = get_expression_code(stmt['loopExpression']) if stmt.get('loopExpression') else ''
        body = get_block_code(stmt['body'])
        code = f'        for ({init_stmt.strip(";")}; {condition}; {loop_expr}) {body}\n'
        return code
    elif stmt['nodeType'] == 'EmitStatement':
        # Emit 事件的表达式生成
        event_call = get_expression_code(stmt['eventCall'])
        return f'        emit {event_call};'
    elif stmt['nodeType'] == 'InlineAssembly':
        # 提取汇编代码块
        assembly_code = stmt['operations']  # 在stmt中找到汇编代码块
        return f'        assembly {{\n            {assembly_code}\n        }}'
    else:
        return f'        // 未实现的语句类型：{stmt["nodeType"]}'

def get_expression_code(expr):
    if expr is None:
        return ''
    if expr['nodeType'] == 'BinaryOperation':
        left = get_expression_code(expr['leftExpression'])
        right = get_expression_code(expr['rightExpression'])
        operator = expr['operator']
        return f'{left} {operator} {right}'
    elif expr['nodeType'] == 'NumberLiteral':
        return expr['number']
    elif expr['nodeType'] == 'BooleanLiteral':
        return str(expr['value']).lower()
    elif expr['nodeType'] == 'stringLiteral':
        return '"' + expr['value'] + '"'
    elif expr['nodeType'] == 'HexLiteral':
        return expr['value']
    elif expr['nodeType'] == 'UnicodeStringLiteral':
        return '"' + expr['value'] + '"'
    elif expr['nodeType'] == 'UnaryOperation':
        sub_expr = get_expression_code(expr['subExpression'])
        operator = expr['operator']
        prefix = expr.get('isPrefix', True)
        if prefix:
            return f'{operator}{sub_expr}'
        else:
            return f'{sub_expr}{operator}'
    elif expr['nodeType'] == 'Identifier':
        return expr['name']
    elif expr['nodeType'] == 'Literal':
        return expr['value']
    elif expr['nodeType'] == 'FunctionCall':
        expression = get_expression_code(expr['expression'])
        arguments = ', '.join([get_expression_code(arg) for arg in expr['arguments']])
        return f'{expression}({arguments})'
    elif expr['nodeType'] == 'MemberAccess':
        expression = get_expression_code(expr['expression'])
        member = expr['memberName']
        return f'{expression}.{member}'
    elif expr['nodeType'] == 'IndexAccess':
        base = get_expression_code(expr['baseExpression'])
        index = get_expression_code(expr['indexExpression'])
        return f'{base}[{index}]'
    elif expr['nodeType'] == 'TupleExpression':
        components = [get_expression_code(component) for component in expr['components']]
        return '({})'.format(', '.join(components))
    elif expr['nodeType'] == 'ElementaryTypeNameExpression':
        # print(expr)
        return expr['typeName']  # 返回类型名称，如 "uint256" 或 "address"
    elif expr['nodeType'] == 'Assignment':  # 新增的Assignment类型处理
        left = get_expression_code(expr['leftHandSide'])
        right = get_expression_code(expr['rightHandSide'])
        operator = expr['operator']
        return f'{left} {operator} {right}'
    else:
        return '/* 未实现的表达式类型：{} */'.format(expr['nodeType'])

# if __name__ == '__main__':
#     if sys.argv[1] in ['--help', '-h']:
#         print("usage: smartupdater_D.py [-h] <contract_source> ")
#         print("\nSmartUpdater Command Line Interface for Contract Conversion")
#         print("\npositional arguments:")
#         print("  contract_source       Path to the Solidity contract source file")
#         print("\noptional arguments:")
#         print("  -h, --help            Show this help message and exit")
#         print("\nExample usage:")
#         print("  $ python smartupdater_D.py ./source.sol")
#     else:
#         input_file = sys.argv[1]
#         # 检查输入文件是否存在
#         if not os.path.exists(input_file):
#             print("Error: The specified contract source file does not exist.")
#             sys.exit(1)  # 使用 sys.exit(1) 表示程序异常退出

def mainfunc(input_file,path):
        # 提取文件名作为逻辑合约名
        contract_name = path
        logic_contract_name = contract_name + "Logic"
        proxy_contract_name = contract_name + "State"
        hyperlayer_contract_name = "Hyperlayer"

        # print("Converting...")

        split_contract(input_file, logic_contract_name, proxy_contract_name, hyperlayer_contract_name)
