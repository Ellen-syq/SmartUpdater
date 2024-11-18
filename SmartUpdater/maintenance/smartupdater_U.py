import sys
import os
import json
import re

def parse_requirements(require_file):
    with open(require_file, 'r') as f:
        content = f.read()

    statements = content.strip().split(';')
    requirements = []

    for stmt in statements:
        stmt = stmt.strip()
        if not stmt:
            continue

        if stmt.startswith('INSERT('):
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
            match = re.match(r'UPDATE\(([^,]+),([^,]+),([^,]+),([^\)]+)\)\s*to\s*\(([^,]+),([^,]+),([^,]+),([^\)]+)\)', stmt)
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

def load_sub_state_vars_info(contract_name, suffix=''):
    filename = f"{contract_name}_sub_state_vars{suffix}.json"
    if not os.path.exists(filename):
        print(f"File {filename} does not exist.")
        return {}
    with open(filename, 'r') as f:
        info = json.load(f)
    return info

def generate_updater_contract(contract_name):
    requirements = parse_requirements('require.txt')

    old_vars_info = load_sub_state_vars_info(contract_name, '_old')
    new_vars_info = load_sub_state_vars_info(contract_name)

    var_types = load_variable_types(contract_name)

    variable_renames = {}
    for req in requirements:
        if req['action'] == 'UPDATE':
            old_name = req['old']['name']
            new_name = req['new']['name']
            variable_renames[old_name] = new_name

    sub_contracts_with_changes = {}
    all_sub_state_indices = set(old_vars_info.keys()) | set(new_vars_info.keys())

    for sub_state_idx in all_sub_state_indices:
        old_vars = set(old_vars_info.get(sub_state_idx, []))
        new_vars = set(new_vars_info.get(sub_state_idx, []))

        renamed_old_vars = set(variable_renames.get(var, var) for var in old_vars)

        vars_to_migrate = renamed_old_vars & new_vars

        if vars_to_migrate != old_vars or vars_to_migrate != new_vars:
            if vars_to_migrate:
                sub_contracts_with_changes[sub_state_idx] = vars_to_migrate
            else:
                pass
        else:
            pass

    if sub_contracts_with_changes:
        generate_updater(contract_name, sub_contracts_with_changes, variable_renames, var_types)
    else:
        print("No sub-contracts require migration.")

def load_variable_types(contract_name):
    var_types_file = f"{contract_name}_var_types.json"
    if not os.path.exists(var_types_file):
        print(f"Variable types file '{var_types_file}' does not exist.")
        return {}
    with open(var_types_file, 'r') as f:
        var_types = json.load(f)
    return var_types

def generate_updater(contract_name, sub_contracts_with_changes, variable_renames, var_types):
    updater_contract_name = f"{contract_name}Updater"

    updater_code = f"pragma solidity ^0.8.0;\n\n"

    for sub_state_idx in sub_contracts_with_changes:
        vars_to_migrate = sub_contracts_with_changes[sub_state_idx]
        old_contract_name = f"{contract_name}Logic{sub_state_idx}"
        updater_code += f"interface IOld{sub_state_idx} {{\n"
        for var_name in vars_to_migrate:
            original_var_name = var_name
            for old_name, new_name in variable_renames.items():
                if new_name == var_name:
                    original_var_name = old_name
                    break
            var_type = var_types.get(original_var_name, 'uint256')
            getter_function_name = f"get_{original_var_name}"
            if 'mapping' in var_type:
                key_type, value_type = parse_mapping_types(var_type)
                updater_code += f"    function {getter_function_name}({key_type} key) external view returns ({value_type});\n"
            else:
                updater_code += f"    function {getter_function_name}() external view returns ({var_type});\n"
        updater_code += "}\n\n"

    for sub_state_idx in sub_contracts_with_changes:
        vars_to_migrate = sub_contracts_with_changes[sub_state_idx]
        new_contract_name = f"{contract_name}Logic{sub_state_idx}"
        updater_code += f"interface INew{sub_state_idx} {{\n"
        for var_name in vars_to_migrate:
            var_type = var_types.get(var_name, 'uint256')
            setter_function_name = f"set_{var_name}"
            if 'mapping' in var_type:
                key_type, value_type = parse_mapping_types(var_type)
                updater_code += f"    function {setter_function_name}({key_type} key, {value_type} value) external;\n"
            else:
                updater_code += f"    function {setter_function_name}({var_type} value) external;\n"
        updater_code += "}\n\n"

    updater_code += f"contract {updater_contract_name} {{\n"

    for sub_state_idx in sub_contracts_with_changes:
        updater_code += f"    address public oldContract{sub_state_idx};\n"
        updater_code += f"    address public newContract{sub_state_idx};\n"

    # 构造函数
    updater_code += f"\n    constructor("
    params = []
    for sub_state_idx in sub_contracts_with_changes:
        params.append(f"address _oldContract{sub_state_idx}")
        params.append(f"address _newContract{sub_state_idx}")
    updater_code += ', '.join(params)
    updater_code += ") {\n"
    for sub_state_idx in sub_contracts_with_changes:
        updater_code += f"        oldContract{sub_state_idx} = _oldContract{sub_state_idx};\n"
        updater_code += f"        newContract{sub_state_idx} = _newContract{sub_state_idx};\n"
    updater_code += f"    }}\n\n"

    updater_code += f"    function updateState() public {{\n"
    for sub_state_idx, vars_to_migrate in sub_contracts_with_changes.items():
        updater_code += f"        {{\n"
        updater_code += f"            IOld{sub_state_idx} oldContract = IOld{sub_state_idx}(oldContract{sub_state_idx});\n"
        updater_code += f"            INew{sub_state_idx} newContract = INew{sub_state_idx}(newContract{sub_state_idx});\n"
        for var_name in vars_to_migrate:
            original_var_name = var_name
            for old_name, new_name in variable_renames.items():
                if new_name == var_name:
                    original_var_name = old_name
                    break
            var_type = var_types.get(original_var_name, 'uint256')
            getter_function_name = f"get_{original_var_name}"
            setter_function_name = f"set_{var_name}"
            if 'mapping' in var_type:
                key_type, value_type = parse_mapping_types(var_type)
                key_list_name = f"key_of_{original_var_name}"
                updater_code += f"            {key_type}; "
                updater_code += f"            for (uint256 i = 0; i < {key_list_name}.length; i++) {{\n"
                updater_code += f"                {key_type} key = {key_list_name}[i];\n"
                updater_code += f"                {value_type} value = oldContract.{getter_function_name}(key);\n"
                updater_code += f"                newContract.{setter_function_name}(key, value);\n"
                updater_code += f"            }}\n"
            else:
                updater_code += f"            {var_type} value = oldContract.{getter_function_name}();\n"
                updater_code += f"            newContract.{setter_function_name}(value);\n"
        updater_code += f"        }}\n\n"
    updater_code += f"    }}\n"
    updater_code += f"}}\n"

    updater_contract_file = f"{updater_contract_name}.sol"
    with open(updater_contract_file, 'w') as f:
        f.write(updater_code)

    print(f"Updater contract written to '{updater_contract_file}'")

def parse_mapping_types(mapping_str):
    match = re.match(r'mapping\((.+?)\s*=>\s*(.+?)\)', mapping_str)
    if match:
        key_type = match.group(1).strip()
        value_type = match.group(2).strip()
        return key_type, value_type
    else:
        return 'unknown', 'unknown'

if __name__ == '__main__':
    if sys.argv[1] in ['--help', '-h']:
        print("usage: smartupdater_U.py [-h] <contract_name> ")
        print("\nSmartUpdater Command Line Interface for Contract Conversion")
        print("\npositional arguments:")
        print("  contract_name       Name of the Solidity contract")
        print("\noptional arguments:")
        print("  -h, --help            Show this help message and exit")

    else:
        contract_name = sys.argv[1]
        generate_updater_contract(contract_name)
