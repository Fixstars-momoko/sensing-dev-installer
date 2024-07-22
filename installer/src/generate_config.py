import os
from pathlib import Path

import sys

import requests
import yaml
import json

import argparse


src_dir = os.path.dirname(__file__)
installer_dir = Path(src_dir).parent.absolute()
root_dir = Path(installer_dir).parent.absolute()

def remove_v(version):
    if version.startswith('v'):
        return version[1:]
    else:
        return version

def generate_url(cmp, version, pf):
    updated_ver = version
    url = ''

    if cmp == 'aravis':
        url = 'https://github.com/Sensing-Dev/aravis/releases/download/' + version
        if pf == 'Windows':
            if version == '0.8.30-internal':
                url = 'https://github.com/Sensing-Dev/aravis/releases/download/internal-0.8.30/aravis-internal-0.8.30-win64.zip'
            else:
                url += '/aravis-' + version + '-win64.zip'
        elif pf == 'Linux':
            if version == '0.8.30-internal':
                url = 'https://github.com/Sensing-Dev/aravis/releases/download/internal-0.8.30/aravis-internal-0.8.30-x86-64-linux.tar.gz'
            else:
                url += '/aravis-' + version + '-x86-64-linux.tar.gz'
        else:
            print('Platform', pf, 'is not supported.')
            sys.exit(1)
    elif cmp =='aravis_dep':
        url = 'https://github.com/Sensing-Dev/aravis/releases/download/' + version
        if pf == 'Windows':
            if version == '0.8.30-internal':
                url = 'https://github.com/Sensing-Dev/aravis/releases/download/internal-0.8.30/Aravis-0.8.30-internal-dependencies.zip'
            else:
                url += '/Aravis-' + version + '-dependencies.zip'
        elif pf == 'Linux':
            return None, updated_ver
        else:
            print('Platform', pf, 'is not supported.')
            sys.exit(1)
    elif cmp == 'ion_kit':
        url = 'https://github.com/fixstars/ion-kit/releases/download/' + version
        if pf == 'Windows':
            url += '/ion-kit-' + remove_v(version) + '-x86-64-windows.zip'
        elif pf == 'Linux':
            url += '/ion-kit-' + remove_v(version) + '-x86-64-linux.tar.gz'
        else:
            print('Platform', pf, 'is not supported.')
            sys.exit(1)
    elif cmp == 'opencv':
        if pf == 'Windows':
            if version == '4.5.2':
                url = 'https://github.com/opencv/opencv/releases/download/4.5.2/opencv-4.5.2-vc14_vc15.exe'
            elif version == '4.5.5':
                url = 'https://github.com/opencv/opencv/releases/download/4.5.5/opencv-4.5.5-vc14_vc15.exe'
            elif version == '4.10.0':
                url = 'https://github.com/opencv/opencv/releases/download/4.10.0/opencv-4.10.0-windows.exe'
            else:
                print('OpenCV', version, 'is not supported on', pf)
                sys.exit(1)
        elif pf == 'Linux':
            updated_ver = '4.5.2'
            if updated_ver == '4.5.2':
                url += 'https://ion-kit.s3.us-west-2.amazonaws.com/dependencies/OpenCV-4.5.2-x86_64-gcc75.sh'
            else:
                print('OpenCV', version, 'is not supported on', pf)
        else:
            print('Platform', pf, 'is not supported.')
            sys.exit(1)
    elif cmp == 'gendc_separator':
        if pf == 'Windows' or pf =='Linux':
            url = 'https://github.com/Sensing-Dev/GenDC/releases/download/' + version + '/gendc_separator_' + version + '_win64.zip'
    else:
        print(cmp, 'is not supported')
        sys.exit(1)

    r = requests.get(url)
    if r.status_code == requests.codes.ok:
        return url, updated_ver
    
    print(url, 'does not exist')
    sys.exit(1)

def get_latest_tag(owner, repo):
    url = f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
    response = requests.get(url)
    response.raise_for_status() 
    release_data = response.json()
    
    if 'tag_name' in release_data:
        return release_data['tag_name']
    else:
        return None
    
if __name__ == '__main__':

    parser = argparse.ArgumentParser(description="Generate config")
    parser.add_argument('-p', '--platform', default='all', type=str, choices=['Windows', 'Linux', 'all'],  help='Which OS installer script needs this config?')
    parser.add_argument('-v', '--version', default='latest', type=str, help='In the release workflow, specify the tag')
    
    argvs = parser.parse_args()
    config_platform = ['Windows', 'Linux'] if argvs.platform == 'all' else [argvs.platform] 
    version = get_latest_tag('Sensing-Dev', 'sensing-dev-installer') if argvs.version == 'latest' else argvs.version

    print(config_platform, version)

    input_file_name = 'config.yml'

    comp_names = ['aravis', 'aravis_dep', 'ion_kit', 'opencv', 'gendc_separator']

    dst_dir = os.path.join(root_dir, 'build')
    if not os.path.exists(dst_dir):
        os.makedirs(dst_dir)

    with open(os.path.join(installer_dir, input_file_name)) as yml_ifs:
        try:
            yml_content = yaml.safe_load(yml_ifs)
        except yaml.YAMLError as exc:
            print(exc)
            sys.exit(1)
        for pf in config_platform:
            out = {}
            for cmp_name in comp_names:
                j = {}
                cmp_version = yml_content['libraries'][cmp_name]['version']

                url, updated_ver = generate_url(cmp_name, cmp_version, pf)
                if url:
                    print(url)
                    j['version'] = updated_ver
                    j['pkg_url'] = url
                    j['name'] = yml_content['libraries'][cmp_name]['name']

                    if pf == 'Windows':
                        j['pkg_sha'] = yml_content['libraries'][cmp_name]['pkg_sha']

                out[cmp_name] = j

            out['sensing_dev'] = {
                'name' : 'sensing-dev',
                'version' : version
            }

            with open(os.path.join(dst_dir, 'config_' + pf+ '.json'), 'w', encoding='utf-8') as f:
                json.dump(out, f, indent=4)

    
