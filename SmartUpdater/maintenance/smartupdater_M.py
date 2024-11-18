import sys
import os
import re
import json
from solcx import compile_standard, install_solc,get_installed_solc_versions
import solidityVersion
from packaging import version
import smartupdater_D


def load_sub_state_vars_info(contract_name):
    with open(f"{contract_name}_sub_state_vars_old.json", 'r') as f:
        info = json.load(f)
    return info

def load_mappings(contract_name):
    with open(f"{contract_name}_var_mapping.json", 'r') as f:
        var_mapping = json.load(f)
    with open(f"{contract_name}_func_mapping.json", 'r') as f:
        func_mapping = json.load(f)
    return var_mapping, func_mapping


def apply_requirements_to_sub_state_contracts(contract_name, requirements):
    sub_state_vars_info = load_sub_state_vars_info(contract_name)
    var_mapping, func_mapping = load_mappings(contract_name)

    sub_contracts_to_delete = set()

    # 对每个需求，应用更改到子状态和子逻辑合约
    for req in requirements:
        if req['action'] == 'DELETE':
            var_name = req['name']
            if var_name in var_mapping:
                sub_state_idx = var_mapping[var_name]
                sub_contract_name = f"{contract_name}State{sub_state_idx}"
                sub_logic_contract_name = f"{contract_name}Logic{sub_state_idx}"
                sub_contract_file = f"{sub_contract_name}.sol"
                sub_logic_contract_file = f"{sub_logic_contract_name}.sol"

                modify_sub_state_contract_delete_var(sub_contract_file, var_name)

                sub_state_vars_info[str(sub_state_idx)].remove(var_name)
                if not sub_state_vars_info[str(sub_state_idx)]:

                    sub_contracts_to_delete.add(sub_state_idx)
                
            else:
                print(f"Variable '{var_name}' not found in any sub-state contract.")
        elif req['action'] == 'UPDATE':
            old_name = req['old']['name']
            new_name = req['new']['name']
            if old_name in var_mapping:
                sub_state_idx = var_mapping[old_name]
                sub_contract_name = f"{contract_name}State{sub_state_idx}"
                sub_logic_contract_name = f"{contract_name}Logic{sub_state_idx}"
                sub_contract_file = f"{sub_contract_name}.sol"
                sub_logic_contract_file = f"{sub_logic_contract_name}.sol"

                # 修改子状态合约
                modify_sub_state_contract_update_var(sub_contract_file, req['old'], req['new'])

                # 修改子逻辑合约
                modify_sub_logic_contract_update_var(sub_logic_contract_file, req['old'], req['new'])

                sub_state_vars_info[str(sub_state_idx)].remove(old_name)
                sub_state_vars_info[str(sub_state_idx)].append(new_name)
                var_mapping.pop(old_name)
                var_mapping[new_name] = sub_state_idx
            else:
                print(f"Variable '{old_name}' not found in any sub-state contract.")
        elif req['action'] == 'INSERT':
            first_sub_state_idx = min(int(idx) for idx in sub_state_vars_info.keys())
            sub_contract_name = f"{contract_name}State{first_sub_state_idx}"
            sub_logic_contract_name = f"{contract_name}Logic{first_sub_state_idx}"
            sub_contract_file = f"{sub_contract_name}.sol"
            sub_logic_contract_file = f"{sub_logic_contract_name}.sol"

            modify_sub_state_contract_insert_var(sub_contract_file, req)

            modify_sub_logic_contract_insert_var(sub_logic_contract_file, req)

            var_name = req['name']
            sub_state_vars_info[str(first_sub_state_idx)].append(var_name)
            var_mapping[var_name] = first_sub_state_idx
        else:
            print(f"Unknown action: {req['action']}")

    for sub_state_idx in sub_contracts_to_delete:
        sub_contract_name = f"{contract_name}State{sub_state_idx}"
        sub_logic_contract_name = f"{contract_name}Logic{sub_state_idx}"
        sub_contract_file = f"{sub_contract_name}.sol"
        sub_logic_contract_file = f"{sub_logic_contract_name}.sol"

        if os.path.exists(sub_contract_file):
            os.remove(sub_contract_file)
            print(f"Deleted sub-state contract '{sub_contract_file}'")
        if os.path.exists(sub_logic_contract_file):
            os.remove(sub_logic_contract_file)
            print(f"Deleted sub-logic contract '{sub_logic_contract_file}'")

        sub_state_vars_info.pop(str(sub_state_idx))

        vars_to_remove = [var for var, idx in var_mapping.items() if idx == sub_state_idx]
        for var in vars_to_remove:
            var_mapping.pop(var)


    with open(f"{contract_name}_var_mapping.json", 'w') as f:
        json.dump(var_mapping, f)
    with open(f"{contract_name}_sub_state_vars.json", 'w') as f:
        json.dump(sub_state_vars_info, f)

def modify_sub_state_contract_delete_var(sub_contract_file, var_name):

    with open(sub_contract_file, 'r') as f:
        content = f.read()

    solc_version = extract_solidity_version(content)

    install_solc_version(solc_version)


    ast = solidityVersion.parse_solidity_code_with_solc(content)

    contracts = {}
    for node in ast['nodes']:
        if node['nodeType'] == 'ContractDefinition':
            contracts[node['name']] = node

    if not contracts:
        print("No contract definition found.")
        return

    original_contract_name = list(contracts.keys())[0]
    contract_def = contracts[original_contract_name]

    new_nodes = []
    for item in contract_def['nodes']:
        if item['nodeType'] == 'VariableDeclaration' and item['name'] == var_name:
            continue  
        else:
            new_nodes.append(item)
    contract_def['nodes'] = new_nodes

    # 生成更新后的代码
    updated_code = unparse_ast(ast)

    with open(sub_contract_file, 'w') as f:
        f.write(updated_code)
    print(f"Updated sub-state contract '{sub_contract_file}' after deleting variable '{var_name}'")

def modify_sub_logic_contract_delete_var(sub_logic_contract_file, var_name):

    with open(sub_logic_contract_file, 'r') as f:
        content = f.read()

    solc_version = extract_solidity_version(content)
    install_solc_version(solc_version)



    ast = solidityVersion.parse_solidity_code_with_solc(content)


    contracts = {}
    for node in ast['nodes']:
        if node['nodeType'] == 'ContractDefinition':
            contracts[node['name']] = node

    if not contracts:
        print("No contract definition found.")
        return

    original_contract_name = list(contracts.keys())[0]
    contract_def = contracts[original_contract_name]

    new_nodes = []
    for item in contract_def['nodes']:
        if item['nodeType'] == 'VariableDeclaration' and item['name'] == var_name:
            continue  
        else:
            if item['nodeType'] == 'FunctionDefinition':
                remove_variable_operations_in_function(item, var_name)
                if is_function_body_empty(item):
                    continue
            new_nodes.append(item)
    contract_def['nodes'] = new_nodes

    updated_code = unparse_ast(ast)

    with open(sub_logic_contract_file, 'w') as f:
        f.write(updated_code)
    print(f"Updated sub-logic contract '{sub_logic_contract_file}' after deleting variable '{var_name}'")

def remove_variable_operations_in_function(function_def, var_name):
    if 'body' in function_def and function_def['body']:
        remove_variable_operations_in_block(function_def['body'], var_name)

def remove_variable_operations_in_block(block, var_name):
    if block['nodeType'] == 'Block':
        statements = []
        for stmt in block['statements']:
            statements.append(stmt)

        new_statements = []
        for stmt in statements:
            type = stmt['nodeType']
            if not statement_uses_variable(stmt, var_name):
                new_statements.append(stmt)
        block['statements'] = new_statements
    else:
        new_statements = []
        if not statement_uses_variable(block, var_name):
            new_statements.append(block)
        block['statements'] = new_statements



def statement_uses_variable(stmt,type, var_name):
    if isinstance(stmt, list):
        for item in stmt:
            if statement_uses_variable(item, var_name):
                return True

    else:
        if stmt['nodeType'] == 'ExpressionStatement':
            return expression_uses_variable(stmt['expression'], var_name)
        elif stmt['nodeType'] == 'Return':
            return expression_uses_variable(stmt.get('expression'), var_name)
        elif stmt['nodeType'] == 'VariableDeclarationStatement':
            if stmt.get('initialValue') and expression_uses_variable(stmt['initialValue'], var_name):
                return True
            for var in stmt.get('declarations', []):
                if var and var['name'] == var_name:
                    return True
        elif stmt['nodeType'] == 'IfStatement':
            if expression_uses_variable(stmt['condition'], var_name):
                return True
            if statement_uses_variable(stmt['trueBody'], var_name):
                return True
            if stmt.get('falseBody') and statement_uses_variable(stmt['falseBody'], var_name):
                return True
        elif stmt['nodeType'] == 'ForStatement':
            if stmt.get('initializationExpression') and statement_uses_variable(stmt['initializationExpression'], var_name):
                return True
            if stmt.get('conditionExpression') and expression_uses_variable(stmt['conditionExpression'], var_name):
                return True
            if stmt.get('loopExpression') and expression_uses_variable(stmt['loopExpression'], var_name):
                return True
            if statement_uses_variable(stmt['body'], var_name):
                return True
        else:
            for key, value in stmt.items():
                if isinstance(value, (dict, list)) and statement_uses_variable(value, var_name):
                    return True

    return False

def expression_uses_variable(expr, var_name):
    if expr is None:
        return False
    if isinstance(expr, dict):
        
        if expr.get('name') == var_name:
            return True
        else:
            for key, value in expr.items():
                if isinstance(value, (dict, list)) and expression_uses_variable(value, var_name):
                    return True
    elif isinstance(expr, list):
        for item in expr:
            if expression_uses_variable(item, var_name):
                return True
    return False

def is_function_body_empty(function_def):
    if 'body' in function_def and function_def['body']:
        body = function_def['body']
        if body['nodeType'] == 'Block' and not body.get('statements'):
            return True
    return False

def modify_sub_state_contract_update_var(sub_contract_file, old_var, new_var):
    with open(sub_contract_file, 'r') as f:
        content = f.read()

    solc_version = extract_solidity_version(content)
    install_solc_version(solc_version)


    ast = solidityVersion.parse_solidity_code_with_solc(content)

    contracts = {}
    for node in ast['nodes']:
        if node['nodeType'] == 'ContractDefinition':
            contracts[node['name']] = node

    if not contracts:
        print("No contract definition found.")
        return

    original_contract_name = list(contracts.keys())[0]
    contract_def = contracts[original_contract_name]

    for item in contract_def['nodes']:
        if item['nodeType'] == 'VariableDeclaration' and item['name'] == old_var['name']:
            item['name'] = new_var['name']
            item['typeName'] = parse_type_name(new_var['type'])
            item['visibility'] = new_var['visibility'] if new_var['visibility'] != '-' else item['visibility']
            if new_var['value'] != '-':
                item['value'] = parse_expression(new_var['value'])
            else:
                item['value'] = None
            break

    updated_code = unparse_ast(ast)

    with open(sub_contract_file, 'w') as f:
        f.write(updated_code)
    print(f"Updated sub-state contract '{sub_contract_file}' after updating variable '{old_var['name']}' to '{new_var['name']}'")

def modify_sub_logic_contract_update_var(sub_logic_contract_file, old_var, new_var):
    with open(sub_logic_contract_file, 'r') as f:
        content = f.read()

    solc_version = extract_solidity_version(content)
    install_solc_version(solc_version)



    ast = solidityVersion.parse_solidity_code_with_solc(content)

    contracts = {}
    for node in ast['nodes']:
        if node['nodeType'] == 'ContractDefinition':
            contracts[node['name']] = node

    if not contracts:
        print("No contract definition found.")
        return

    original_contract_name = list(contracts.keys())[0]
    contract_def = contracts[original_contract_name]

    for item in contract_def['nodes']:
        if item['nodeType'] == 'VariableDeclaration' and item['name'] == old_var['name']:
            item['name'] = new_var['name']
            item['typeName'] = parse_type_name(new_var['type'])
            item['visibility'] = new_var['visibility'] if new_var['visibility'] != '-' else item['visibility']
            if new_var['value'] != '-':
                item['value'] = parse_expression(new_var['value'])
            else:
                item['value'] = None

            if item['visibility'] == 'private':
                setter_function = create_setter_function(item['name'], new_var['type'])
                contract_def['nodes'].append(setter_function)
            break

    for item in contract_def['nodes']:
        if item['nodeType'] == 'FunctionDefinition':
            replace_variable_in_node(item, old_var['name'], new_var['name'])

    updated_code = unparse_ast(ast)

    with open(sub_logic_contract_file, 'w') as f:
        f.write(updated_code)
    print(f"Updated sub-logic contract '{sub_logic_contract_file}' after updating variable '{old_var['name']}' to '{new_var['name']}'")

def replace_variable_in_node(node, old_name, new_name):
    if isinstance(node, dict):
        if node.get('nodeType') == 'Identifier' and node.get('name') == old_name:
            node['name'] = new_name
        else:
            for key, value in node.items():
                if isinstance(value, (dict, list)):
                    replace_variable_in_node(value, old_name, new_name)
    elif isinstance(node, list):
        for item in node:
            replace_variable_in_node(item, old_name, new_name)

def modify_sub_state_contract_insert_var(sub_contract_file, req):

    with open(sub_contract_file, 'r') as f:
        content = f.read()

    solc_version = extract_solidity_version(content)
    install_solc_version(solc_version)


    ast = solidityVersion.parse_solidity_code_with_solc(content)

    contracts = {}
    for node in ast['nodes']:
        if node['nodeType'] == 'ContractDefinition':
            contracts[node['name']] = node

    if not contracts:
        print("No contract definition found.")
        return

    original_contract_name = list(contracts.keys())[0]
    contract_def = contracts[original_contract_name]

    new_var_decl = create_state_variable_declaration(
        req['name'],
        req['type'],
        req['value'],
        req['visibility']
    )

    contract_def['nodes'].append(new_var_decl)

    updated_code = unparse_ast(ast)

    with open(sub_contract_file, 'w') as f:
        f.write(updated_code)
    print(f"Inserted variable '{req['name']}' into sub-state contract '{sub_contract_file}'")


def modify_sub_logic_contract_insert_var(sub_logic_contract_file, req):

    with open(sub_logic_contract_file, 'r') as f:
        content = f.read()

    solc_version = extract_solidity_version(content)
    install_solc_version(solc_version)

    ast = solidityVersion.parse_solidity_code_with_solc(content)

    contracts = {}
    for node in ast['nodes']:
        if node['nodeType'] == 'ContractDefinition':
            contracts[node['name']] = node

    if not contracts:
        print("No contract definition found.")
        return

    original_contract_name = list(contracts.keys())[0]
    contract_def = contracts[original_contract_name]

    new_var_decl = create_state_variable_declaration(
        req['name'],
        req['type'],
        req['value'],
        req['visibility']
    )

    contract_def['nodes'].append(new_var_decl)


    if req['visibility'] == 'private':
        setter_function = create_setter_function(req['name'], req['type'])
        contract_def['nodes'].append(setter_function)

    # 生成更新后的代码
    updated_code = unparse_ast(ast)

    with open(sub_logic_contract_file, 'w') as f:
        f.write(updated_code)
    print(f"Inserted variable '{req['name']}' into sub-logic contract '{sub_logic_contract_file}'")

def create_setter_function(var_name, var_type_str):
    # 检查变量类型是否为映射
    if var_type_str.startswith('mapping'):
        key_type_str, value_type_str = parse_mapping_types(var_type_str)

        function_node = {
            'nodeType': 'FunctionDefinition',
            'name': f'set_{var_name}',
            'parameters': {
                'parameters': [
                    {
                        'nodeType': 'VariableDeclaration',
                        'typeName': parse_type_name(key_type_str),
                        'name': 'key',
                        'storageLocation': 'default',
                        'isStateVar': False,
                        'isIndexed': False
                    },
                    {
                        'nodeType': 'VariableDeclaration',
                        'typeName': parse_type_name(value_type_str),
                        'name': 'value',
                        'storageLocation': 'default',
                        'isStateVar': False,
                        'isIndexed': False
                    }
                ]
            },
            'visibility': 'public',
            'stateMutability': 'nonpayable',
            'isConstructor': False,
            'isFallback': False,
            'isVirtual': False,
            'override': None,
            'body': {
                'nodeType': 'Block',
                'statements': [
                    {
                        'nodeType': 'ExpressionStatement',
                        'expression': {
                            'nodeType': 'Assignment',
                            'operator': '=',
                            'leftHandSide': {
                                'nodeType': 'IndexAccess',
                                'baseExpression': {
                                    'nodeType': 'Identifier',
                                    'name': var_name
                                },
                                'indexExpression': {
                                    'nodeType': 'Identifier',
                                    'name': 'key'
                                }
                            },
                            'rightHandSide': {
                                'nodeType': 'Identifier',
                                'name': 'value'
                            }
                        }
                    }
                ]
            }
        }
        return function_node
    else:
        setter_function = {
            'nodeType': 'FunctionDefinition',
            'name': f'set_{var_name}',
            'parameters': {
                'parameters': [
                    {
                        'nodeType': 'VariableDeclaration',
                        'typeName': parse_type_name(var_type_str),
                        'name': f'_{var_name}',
                        'storageLocation': 'default',
                        'isStateVar': False,
                        'isIndexed': False
                    }
                ]
            },
            'visibility': 'public',
            'stateMutability': 'nonpayable',
            'isConstructor': False,
            'isFallback': False,
            'isVirtual': False,
            'override': None,
            'body': {
                'nodeType': 'Block',
                'statements': [
                    {
                        'nodeType': 'ExpressionStatement',
                        'expression': {
                            'nodeType': 'Assignment',
                            'operator': '=',
                            'leftHandSide': {
                                'nodeType': 'Identifier',
                                'name': var_name
                            },
                            'rightHandSide': {
                                'nodeType': 'Identifier',
                                'name': f'_{var_name}'
                            }
                        }
                    }
                ]
            }
        }
        return setter_function

def parse_mapping_types(mapping_str):
    match = re.match(r'mapping\((.+?)\s*=>\s*(.+?)\)', mapping_str)
    if match:
        key_type = match.group(1).strip()
        value_type = match.group(2).strip()
        return key_type, value_type
    else:
        return 'unknown', 'unknown'


def parse_requirements(require_file):
    with open(require_file, 'r') as f:
        content = f.read()

    # 分割语句
    statements = content.strip().split(';')
    requirements = []

    for stmt in statements:
        stmt = stmt.strip()
        if not stmt:
            continue

        if stmt.startswith('INSERT('):
            # INSERT(i,t,v,m)
            match = re.match(r'INSERT\(([^,]+),([^,]+),([^,]+),([^\)]+)\)', stmt)
            if match:
                i, t, v, m = match.groups()
                requirements.append({
                    'action': 'INSERT',
                    'name': i.strip(),
                    'type': t.strip(),
                    'value': v.strip(),
                    'visibility': m.strip()
                })
            else:
                print(f"Invalid INSERT statement: {stmt}")
        elif stmt.startswith('DELETE('):
            # DELETE(i,-,-,-)
            match = re.match(r'DELETE\(([^,]+),-,-,-\)', stmt)
            if match:
                i = match.group(1)
                requirements.append({
                    'action': 'DELETE',
                    'name': i.strip()
                })
            else:
                print(f"Invalid DELETE statement: {stmt}")
        elif stmt.startswith('UPDATE('):
            # UPDATE(i,t,v,m) to(i,t,v,m)
            match = re.match(r'UPDATE\(([^,]+),([^,]+),([^,]+),([^\)]+)\) to\(([^,]+),([^,]+),([^,]+),([^\)]+)\)', stmt)
            if match:
                i_old, t_old, v_old, m_old, i_new, t_new, v_new, m_new = match.groups()
                requirements.append({
                    'action': 'UPDATE',
                    'old': {
                        'name': i_old.strip(),
                        'type': t_old.strip(),
                        'value': v_old.strip(),
                        'visibility': m_old.strip()
                    },
                    'new': {
                        'name': i_new.strip(),
                        'type': t_new.strip(),
                        'value': v_new.strip(),
                        'visibility': m_new.strip()
                    }
                })
            else:
                print(f"Invalid UPDATE statement: {stmt}")
        else:
            print(f"Unknown statement: {stmt}")

    return requirements

def create_state_variable_declaration(var_name, var_type_str, var_value_str, visibility_str):
    var_decl = {
        'nodeType': 'VariableDeclaration',
        'name': var_name,
        'typeName': parse_type_name(var_type_str),
        'storageLocation': 'default',
        'visibility': visibility_str if visibility_str != '-' else 'internal',
        'constant': False,
        'stateVariable': True,
        'value': None
    }
    if var_value_str != '-':
        var_decl['value'] = parse_expression(var_value_str)

    return var_decl

def parse_type_name(type_str):
    if type_str.startswith('mapping'):
        key_type_str, value_type_str = parse_mapping_types(type_str)
        return {
            'nodeType': 'Mapping',
            'keyType': parse_type_name(key_type_str),
            'valueType': parse_type_name(value_type_str)
        }
    elif type_str.endswith('[]'):
        base_type_str = type_str[:-2]
        return {
            'nodeType': 'ArrayTypeName',
            'baseType': parse_type_name(base_type_str),
            'length': None
        }
    else:
        return {
            'nodeType': 'ElementaryTypeName',
            'name': type_str
        }

def parse_expression(value_str):
    if value_str.isdigit():
        return {
            'nodeType': 'Literal',
            'kind': 'number',
            'value': value_str,
            'typeDescriptions': {
                'typeString': 'uint256'
            }
        }
    elif value_str.startswith('"') and value_str.endswith('"'):
        return {
            'nodeType': 'Literal',
            'kind': 'string',
            'value': value_str,
            'typeDescriptions': {
                'typeString': 'string'
            }
        }
    elif value_str in ['true', 'false']:
        return {
            'nodeType': 'Literal',
            'kind': 'bool',
            'value': value_str,
            'typeDescriptions': {
                'typeString': 'bool'
            }
        }
    else:
        return {
            'nodeType': 'Identifier',
            'name': value_str
        }

def unparse_ast(ast):
    code = ''
    for node in ast['nodes']:
        if node['nodeType'] == 'PragmaDirective':
            # print("node--------------------")
            # print(node)
            code += f"pragma {node['literals'][0]} {node['literals'][1]}{''.join(node['literals'][2:])};\n"
        elif node['nodeType'] == 'ContractDefinition':
            code += f"contract {node['name']} {{\n"
            for subnode in node['nodes']:
                if subnode['nodeType'] == 'VariableDeclaration':
                    var = subnode
                    var_type = get_type_description(var['typeName'])
                    var_name = var['name']
                    visibility = var.get('visibility', 'internal')
                    var_code = f"    {var_type} {visibility} {var_name}"
                    if var.get('value'):
                        var_value = get_expression_code(var['value'])
                        var_code += f" = {var_value}"
                    var_code += ";\n"
                    code += var_code
                elif subnode['nodeType'] == 'FunctionDefinition':
                    func_code = get_function_definition(subnode)
                    code += func_code + '\n'
            code += '}\n'
        else:
            pass

    return code




def get_type_description(type_node):
    if type_node['nodeType'] == 'ElementaryTypeName':
        return type_node['name']
    elif type_node['nodeType'] == 'UserDefinedTypeName':
        return type_node['namePath']
    elif type_node['nodeType'] == 'Mapping':
        from_type = get_type_description(type_node['keyType'])
        to_type = get_type_description(type_node['valueType'])
        return f"mapping({from_type} => {to_type})"
    elif type_node['nodeType'] == 'ArrayTypeName':
        base_type = get_type_description(type_node['baseType'])
        length = type_node.get('length')
        if length:
            return f"{base_type}[{length['number']}]"
        else:
            return f"{base_type}[]"
    else:
        return 'unknown'

def get_expression_code(expr):
    if expr is None:
        return ''
    if expr['nodeType'] == 'Literal':
        return expr['value']
    elif expr['nodeType'] == 'Identifier':
        return expr['name']
    else:
        return ''

def get_function_definition(func):
    name = func['name'] if func['name'] else ''
    params = get_parameter_list(func.get('parameters'))
    visibility = func.get('visibility', '')
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

        stmt_code = smartupdater_D.get_statement_code(block)
        return '{\n' + stmt_code + '\n    }'
    else:
        statements = []
        for stmt in block['statements']:
            stmt_code = smartupdater_D.get_statement_code(stmt)
            statements.append(stmt_code)
        return '{\n' + '\n'.join(statements) + '\n    }'


def extract_solidity_version(code):

    pragma_regex = r'pragma\s+solidity\s+[\^\s]?([0-9.]+);'
    match = re.search(pragma_regex, code)
    if match:
        version_spec = match.group(1).strip()
        version_number = version_spec.lstrip('^').split(' ')[0]
        return version_number
    else:
        raise ValueError("Pragma statement not found in the Solidity code.")

def install_solc_version(solc_version):
    installed_versions = get_installed_solc_versions()
    if solc_version not in installed_versions:
        install_solc(solc_version)
    else:
        print(f"solc version {solc_version} is already installed.")


def main(argv1,argv2):

    contract_name = argv1
    require_file = argv2

    if not os.path.exists(require_file):
        print(f"Requirement file '{require_file}' does not exist.")
        sys.exit(1)

    requirements = parse_requirements(require_file)

    apply_requirements_to_sub_state_contracts(contract_name, requirements)
