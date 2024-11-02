import subprocess
import json
import re
import os
import tempfile
from solcx import install_solc, set_solc_version, get_installed_solc_versions
from solcx.install import get_executable
from solcx.exceptions import SolcNotInstalled

def extract_solidity_version(code):
    """
    提取 Solidity 版本号。
    """
    pragma_regex = r'pragma\s+solidity\s+[\^\s]?([0-9.]+);'
    match = re.search(pragma_regex, code)
    if match:
        version = match.group(1).strip()
        # print(f"Detected Solidity version specification: {version}")
        return version
    else:
        raise ValueError("Pragma statement not found in the Solidity code.")

def parse_solidity_code_with_solc(code):
    try:
        # 提取 Solidity 版本号
        solc_version = extract_solidity_version(code)

        # 如果未安装指定版本的 solc，则安装
        if solc_version not in get_installed_solc_versions():
            # print(f"Installing solc version {solc_version}...")
            install_solc(solc_version)
        # else:
            # print(f"solc version {solc_version} is already installed.")

        # 获取已安装的 solc 可执行文件路径
        solc_executable = get_executable(solc_version)
        if not os.path.exists(solc_executable):
            print(f"Failed to locate the solc executable for version {solc_version}.")
            return None
        # else:
            # print(f"Using solc executable at: {solc_executable}")

        # 创建临时文件保存 Solidity 代码
        with tempfile.NamedTemporaryFile(mode='w', suffix='.sol', delete=False) as temp_file:
            temp_file.write(code)
            temp_filename = temp_file.name

        try:
            # 调用 solc 生成 AST，使用 --ast-compact-json
            result = subprocess.run(
                [solc_executable, '--ast-compact-json', temp_filename],
                capture_output=True,
                text=True
            )

            # # 打印 stdout 和 stderr
            # print("solc stdout:")
            # print(result.stdout)
            # print("solc stderr:")
            # print(result.stderr)

            if result.returncode != 0:
                print(f"solc error: {result.stderr}")
                return None

            # 提取 JSON 部分
            stdout = result.stdout

            # 使用正则表达式匹配 JSON 对象
            match = re.search(r'=======.*=======\s*(\{.*\})', stdout, re.DOTALL)
            if match:
                json_content = match.group(1)
            else:
                print("Failed to extract JSON content from solc output.")
                return None

            # 解析 AST JSON 输出
            ast_json = json.loads(json_content)
            return ast_json

        except json.JSONDecodeError as e:
            print(f"Failed to parse AST JSON: {e}")
            return None

        finally:
            # 删除临时文件
            os.remove(temp_filename)

    except ValueError as ve:
        print(f"Error: {ve}")
        return None
    except SolcNotInstalled as sni:
        print(f"Solc installation error: {sni}")
        return None
    except Exception as ex:
        print(f"An unexpected error occurred: {ex}")
        return None
