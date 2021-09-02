#!/usr/bin/env bash

## Build 20210830-001

## 导入通用变量与函数
dir_shell=/ql/shell
. $dir_shell/share.sh


## 调试模式开关，默认是0，表示关闭；设置为1，表示开启
DEBUG="1"

## 本脚本限制的最大线程数量
proc_num="7"

## 备份配置文件开关，默认是1，表示开启；设置为0，表示关闭。备份路径 /ql/config/bak/
BACKUP="1"
## 是否删除指定天数以前的备份文件开关，默认是1，表示开启；设置为0，表示关闭。删除路径 /ql/config/bak/
CLEANBAK="1"
## 定义删除指定天数以前的备份文件
CLEANBAK_DAYS="2"




## 生成pt_pin清单
gen_pt_pin_array() {
  local envs=$(eval echo "\$JD_COOKIE")
  local array=($(echo $envs | sed 's/&/ /g'))
  local tmp1 tmp2 i pt_pin_temp
  for i in "${!array[@]}"; do
    pt_pin_temp=$(echo ${array[i]} | perl -pe "{s|.*pt_pin=([^; ]+)(?=;?).*|\1|; s|%|\\\x|g}")
    remark_name[i]=$(cat $dir_db/env.db | grep ${array[i]} | perl -pe "{s|.*remarks\":\"([^\"]+).*|\1|g}" | tail -1)
    [[ $pt_pin_temp == *\\x* ]] && pt_pin[i]=$(printf $pt_pin_temp) || pt_pin[i]=$pt_pin_temp
  done
}

diy_help_rules(){
    case $1 in
        Fruit)
            tmp_helptype="0"            # 东东农场使用“全部一致互助模板”，所有账户要助力的码全部一致
            ;;
        DreamFactory | JdFactory)
            tmp_helptype="1"            # 京喜工厂和东东工厂使用“均等机会互助模板”，所有账户获得助力次数一致
            ;;
        Jdzz | Joy)
            tmp_helptype="2"            # 京东赚赚和疯狂的Joy使用“随机顺序互助模板”，本套脚本内账号间随机顺序助力，每次生成的顺序都不一致。
            ;;
        *)
            tmp_helptype=$HelpType      # 其他活动仍按默认互助模板生产互助规则。
            ;;
    esac
}

## 导出互助码的通用程序，$1：去掉后缀的脚本名称，$2：config.sh中的后缀，$3：活动中文名称
export_codes_sub() {
    local task_name=$1
    local config_name=$2
    local chinese_name=$3
    local config_name_my=My$config_name
    local config_name_for_other=ForOther$config_name
    local tmp_helptype=$HelpType
    local BreakHelpInterval=$(echo $BreakHelpNum | perl -pe "{s|~|-|; s|_|-|}" | sed 's/\(\d\+\)-\(\d\+\)/{\1..\2}/g')
    local BreakHelpNumArray=($(eval echo $BreakHelpInterval))
    local BreakHelpNumVerify=$(echo $BreakHelpNum | sed 's/ //g' | perl -pe "{s|-||; s|~||; s|_||}" | sed 's/^\d\+$//g')
    local i j k m n t pt_pin_in_log code tmp_grep tmp_my_code tmp_for_other user_num tmp_helptype HelpTemp random_num_list
    local envs=$(eval echo "\$JD_COOKIE")
    local array=($(echo $envs | sed 's/&/ /g'))
    local user_sum=${#array[*]}
    if cd $dir_log/$task_name &>/dev/null && [[ $(ls) ]]; then
        ## 寻找所有互助码以及对应的pt_pin
        i=0
        pt_pin_in_log=()
        code=()
        pt_pin_and_code=$(ls -r *.log | xargs awk -v var="的$chinese_name好友互助码" 'BEGIN{FS="[（ ）】]+"; OFS="&"} $3~var {print $2,$4}')
        for line in $pt_pin_and_code; do
            pt_pin_in_log[i]=$(echo $line | awk -F "&" '{print $1}')
            code[i]=$(echo $line | awk -F "&" '{print $2}')
            let i++
        done

        ## 输出My系列变量
        if [[ ${#code[*]} -gt 0 ]]; then
            for ((m = 0; m < ${#pt_pin[*]}; m++)); do
                tmp_my_code=""
                j=$((m + 1))
                for ((n = 0; n < ${#code[*]}; n++)); do
                    if [[ ${pt_pin[m]} == ${pt_pin_in_log[n]} ]]; then
                        tmp_my_code=${code[n]}
                        break
                    fi
                done
                echo "$config_name_my$j='$tmp_my_code'"
            done
        else
            echo "## 从日志中未找到任何互助码"
        fi

        ## 输出ForOther系列变量
        if [[ ${#code[*]} -gt 0 ]]; then
            [[ $DiyHelpType = "1" ]] && diy_help_rules $2
            case $tmp_helptype in
            0) ## 全部一致
                HelpTemp="全部一致"
                echo -e "\n## 采用\"$HelpTemp\"互助模板："
                tmp_for_other=""
                for ((m = 0; m < ${#pt_pin[*]}; m++)); do
                    j=$((m + 1))
                    if [[ $BreakHelpType = "1" ]]; then
                        if [ "$BreakHelpNumVerify" = "" ]; then
                            for ((t = 0; t < ${#BreakHelpNumArray[*]}; t++)); do
                                [[ "${BreakHelpNumArray[t]}" = "$j" ]] && continue 2
                            done
                            tmp_for_other="$tmp_for_other@\${$config_name_my$j}"
                        else
                            echo -e "\n#【`date +%X`】 变量值填写不规范，请检查后重试！"
                            tmp_for_other="$tmp_for_other@\${$config_name_my$j}"
                        fi
                    else
                        tmp_for_other="$tmp_for_other@\${$config_name_my$j}"
                    fi
                done
                echo "${config_name_for_other}1=\"$tmp_for_other\"" | perl -pe "s|($config_name_for_other\d+=\")@|\1|"
                for ((m = 1; m < ${#pt_pin[*]}; m++)); do
                    j=$((m + 1))
                    echo "$config_name_for_other$j=\"$tmp_for_other\"" | perl -pe "s|($config_name_for_other\d+=\")@|\1|"
                done
                ;;

            1) ## 均等助力
                HelpTemp="均等助力"
                echo -e "\n## 采用\"$HelpTemp\"互助模板："
                for ((m = 0; m < ${#pt_pin[*]}; m++)); do
                    tmp_for_other=""
                    j=$((m + 1))
                    for ((n = $m; n < $(($user_sum + $m)); n++)); do
                        [[ $m -eq $n ]] && continue
                        if [[ $((n + 1)) -le $user_sum ]]; then
                            k=$((n + 1))
                        else
                            k=$((n + 1 - $user_sum))
                        fi
                        if [[ $BreakHelpType = "1" ]]; then
                            if [ "$BreakHelpNumVerify" = "" ]; then
                                for ((t = 0; t < ${#BreakHelpNumArray[*]}; t++)); do
                                    [[ "${BreakHelpNumArray[t]}" = "$k" ]] && continue 2
                                done
                                tmp_for_other="$tmp_for_other@\${$config_name_my$k}"
                            else
                                echo -e "\n#【`date +%X`】 变量值填写不规范，请检查后重试！"
                                tmp_for_other="$tmp_for_other@\${$config_name_my$k}"
                            fi
                        else
                            tmp_for_other="$tmp_for_other@\${$config_name_my$k}"
                        fi
                    done
                    echo "$config_name_for_other$j=\"$tmp_for_other\"" | perl -pe "s|($config_name_for_other\d+=\")@|\1|"
                done
                ;;

            2) ## 本套脚本内账号间随机顺序助力
                HelpTemp="随机顺序"
                echo -e "\n## 采用\"$HelpTemp\"互助模板："
                for ((m = 0; m < ${#pt_pin[*]}; m++)); do
                    tmp_for_other=""
                    random_num_list=$(seq $user_sum | sort -R)
                    j=$((m + 1))
                    for n in $random_num_list; do
                        [[ $j -eq $n ]] && continue
                        if [[ $BreakHelpType = "1" ]]; then
                            if [ "$BreakHelpNumVerify" = "" ]; then
                                for ((t = 0; t < ${#BreakHelpNumArray[*]}; t++)); do
                                    [[ "${BreakHelpNumArray[t]}" = "$n" ]] && continue 2
                                done
                                tmp_for_other="$tmp_for_other@\${$config_name_my$n}"
                            else
                                echo -e "\n#【`date +%X`】 变量值填写不规范，请检查后重试！"
                                tmp_for_other="$tmp_for_other@\${$config_name_my$n}"
                            fi
                        else
                            tmp_for_other="$tmp_for_other@\${$config_name_my$n}"
                        fi
                    done
                    echo "$config_name_for_other$j=\"$tmp_for_other\"" | perl -pe "s|($config_name_for_other\d+=\")@|\1|"
                done
                ;;

            *) ## 按编号优先
                HelpTemp="按编号优先"
                echo -e "\n## 采用\"$HelpTemp\"互助模板"
                for ((m = 0; m < ${#pt_pin[*]}; m++)); do
                    tmp_for_other=""
                    j=$((m + 1))
                    for ((n = 0; n < $user_sum; n++)); do
                        [[ $m -eq $n ]] && continue
                        k=$((n + 1))
                        if [[ $BreakHelpType = "1" ]]; then
                            if [ "$BreakHelpNumVerify" = "" ]; then
                                for ((t = 0; t < ${#BreakHelpNumArray[*]}; t++)); do
                                    [[ "${BreakHelpNumArray[t]}" = "$k" ]] && continue 2
                                done
                                tmp_for_other="$tmp_for_other@\${$config_name_my$k}"
                            else
                                echo -e "\n#【`date +%X`】 变量值填写不规范，请检查后重试！"
                                tmp_for_other="$tmp_for_other@\${$config_name_my$k}"
                            fi
                        else
                            tmp_for_other="$tmp_for_other@\${$config_name_my$k}"
                        fi
                    done
                    echo "$config_name_for_other$j=\"$tmp_for_other\"" | perl -pe "s|($config_name_for_other\d+=\")@|\1|"
                done
                ;;
            esac
        fi
    else
        echo "#【`date +%X`】 未运行过 $task_name.js 脚本，未产生日志"
    fi
}

## 汇总输出
export_all_codes() {
    gen_pt_pin_array
    [[ $DEBUG = "1" ]] && echo -e "\n#【`date +%X`】 当前 code.sh 的线程数量：$ps_num"
    [[ $DEBUG = "1" ]] && echo -e "\n#【`date +%X`】 预设的 JD_COOKIE 数量：`echo $JD_COOKIE | grep -o 'pt_key' | wc -l`"
    [[ $DEBUG = "1" ]] && echo -e "\n#【`date +%X`】 预设的 JD_COOKIE 环境变量数量：`echo $JD_COOKIE | sed 's/&/\n/g' | wc -l`"
    [[ $DEBUG = "1" && "$(echo $JD_COOKIE | sed 's/&/\n/g' | wc -l)" = "1" && "$(echo $JD_COOKIE | grep -o 'pt_key' | wc -l)" -gt 1 ]] && echo -e "\n#【`date +%X`】 检测到您将多个 COOKIES 填写到单个环境变量值，请注意将各 COOKIES 采用 & 分隔，否则将无法完整输出互助码及互助规则！"
    echo -e "\n#【`date +%X`】 从日志提取互助码，编号和配置文件中Cookie编号完全对应，如果为空就是所有日志中都没有。\n\n#【`date +%X`】 即使某个MyXxx变量未赋值，也可以将其变量名填在ForOtherXxx中，jtask脚本会自动过滤空值。\n"
    if [[ $DiyHelpType = "1" ]]; then
        echo -e "#【`date +%X`】 您已启用指定活动采用指定互助模板功能！"
    else
        echo -n "#【`date +%X`】 您选择的互助码模板为："
        case $HelpType in
        0)
            echo "所有账号助力码全部一致。"
            ;;
        1)
            echo "所有账号机会均等助力。"
            ;;
        2)
            echo "本套脚本内账号间随机顺序助力。"
            ;;
    	*)
            echo "按账号编号优先。"
            ;;
        esac
    fi
    [[ $BreakHelpType = "1" ]] && echo -e "\n#【`date +%X`】 您已启用屏蔽模式，账号 $BreakHelpNum 将不被助力！"
    if [ "$ps_num" -gt $proc_num ]; then
        echo -e "\n#【`date +%X`】 检测到 code.sh 的线程过多 ，请稍后再试！"
        exit
    elif [ -z $repo ]; then
        echo -e "\n#【`date +%X`】 未检测到兼容的活动脚本日志，无法读取互助码，退出！"
        exit
    else
        echo -e "\n#【`date +%X`】 默认调用 $repo 的脚本日志，格式化导出互助码，生成互助规则！"
        dump_user_info
        for ((i = 0; i < ${#name_js[*]}; i++)); do
            echo -e "\n## ${name_chinese[i]}："
            export_codes_sub "${name_js[i]}" "${name_config[i]}" "${name_chinese[i]}"
        done
    fi
}

#更新配置文件中互助码的函数
help_codes(){
    local envs=$(eval echo "\$JD_COOKIE")
    local array=($(echo $envs | sed 's/&/ /g'))
    local user_sum=${#array[*]}
    local config_name=$1
    local chinese_name=$2
    local config_name_my=My$config_name
    local config_name_for_other=ForOther$config_name
    local ShareCode_dir="$dir_log/.ShareCode"
    local ShareCode_log="$ShareCode_dir/$config_name.log"
    local i j k

    #更新配置文件中的互助码
    [[ ! -d $ShareCode_dir ]] && mkdir -p $ShareCode_dir
    [[ "$1" = "TokenJxnc" ]] && config_name_my=$1    
    if [ ! -f $ShareCode_log ] || [ -z "$(cat $ShareCode_log | grep "^$config_name_my\d")" ]; then
        echo -e "\n## $chinese_name\n${config_name_my}1=''\n" >> $ShareCode_log
    fi
    for ((i=1; i<=200; i++)); do
        local new_code="$(cat $latest_log_path | grep "^$config_name_my$i=.\+'$" | sed "s/\S\+'\([^']*\)'$/\1/")"
        local old_code="$(cat $ShareCode_log | grep "^$config_name_my$i=.\+'$" | sed "s/\S\+'\([^']*\)'$/\1/")"
        if [[ $i -le $user_sum ]]; then
            if [ -z "$(grep "^$config_name_my$i" $ShareCode_log)" ]; then
                sed -i "/^$config_name_my$[$i-1]='.*'/ s/$/\n$config_name_my$i=\'\'/" $ShareCode_log
            fi
            if [ "$new_code" != "$old_code" ]; then
                if [[ "$new_code" != "undefined" ]] && [[ "$new_code" != "{}" ]]; then
                    sed -i "s/^$config_name_my$i='$old_code'$/$config_name_my$i='$new_code'/" $ShareCode_log
                fi
            fi
        elif [[ $i -gt $user_sum ]] && [[ $i -gt 1 ]]; then
            sed -i "/^$config_name_my$i/d" $ShareCode_log
        elif [[ $i -eq 1 ]] && [[ -z "$new_code" ]]; then
            sed -i "s/^$config_name_my$i='\S*'$/$config_name_my$i=''/" $ShareCode_log
        fi
    done
    sed -i "1c ## 上次导入时间：$(date +%Y年%m月%d日\ %X)" $ShareCode_log
}

#更新配置文件中互助规则的函数
help_rules(){
    local envs=$(eval echo "\$JD_COOKIE")
    local array=($(echo $envs | sed 's/&/ /g'))
    local user_sum=${#array[*]}
    local config_name=$1
    local chinese_name=$2
    local config_name_my=My$config_name
    local config_name_for_other=ForOther$config_name
    local ShareCode_dir="$dir_log/.ShareCode"
    local ShareCode_log="$ShareCode_dir/$config_name.log"
    local i j k

    #更新配置文件中的互助规则
    if [ -z "$(cat $ShareCode_log | grep "^$config_name_for_other\d")" ]; then
    echo -e "${config_name_for_other}1=\"\"" >> $ShareCode_log
    fi
    for ((j=1; j<=200; j++)); do
        local new_rule="$(cat $latest_log_path | grep "^$config_name_for_other$j=.\+\"$" | sed "s/\S\+\"\([^\"]*\)\"$/\1/")"
        local old_rule="$(cat $ShareCode_log | grep "^$config_name_for_other$j=.\+\"$" | sed "s/\S\+\"\([^\"]*\)\"$/\1/")"
        if [[ $j -le $user_sum ]]; then
            if [ -z "$(grep "^$config_name_for_other$j" $ShareCode_log)" ]; then
                sed -i "/^$config_name_for_other$[$j-1]=".*"/ s/$/\n$config_name_for_other$j=\"\"/" $ShareCode_log
            fi
            if [ "$new_rule" != "$old_rule" ]; then
                sed -i "s/^$config_name_for_other$j=\"$old_rule\"$/$config_name_for_other$j=\"$new_rule\"/" $ShareCode_log
            fi
        elif [[ $j -gt $user_sum ]] && [[ $j -gt 1 ]]; then
            sed -i "/^$config_name_for_other$j/d" $ShareCode_log
        elif [[ $j -eq 1 ]] && [[ -z "$new_rule" ]]; then
            sed -i "s/^$config_name_for_other$j=\"\S*\"$/$config_name_for_other$j=\"\"/" $ShareCode_log
        fi
    done
    sed -i "1c ## 上次导入时间：$(date +%Y年%m月%d日\ %X)" $ShareCode_log
}

export_codes_sub_only(){
    if [ "$(cat $dir_scripts/"$repo"_jd_cfd.js | grep "// console.log(\`token")" != "" ]; then
        echo -e "\n# 正在修改 "$repo"_jd_cfd.js ，待完全运行 "$repo"_jd_cfd.js 后即可输出 token ！"
    fi
    sed -i 's/.*\(c.*log\).*\(${JSON.*token)}\).*/      \1(\`\\n【京东账号${$.index}（${$.UserName}）的京喜token好友互助码】\2\\n\`)/g' /ql/scripts/*_jd_cfd.js
    local task_name=$1
    local config_name=$2
    local chinese_name=$3
    local i j k m n pt_pin_in_log code tmp_grep tmp_my_code tmp_for_other user_num random_num_list
    local envs=$(eval echo "\$JD_COOKIE")
    local array=($(echo $envs | sed 's/&/ /g'))
    local user_sum=${#array[*]}
    if cd $dir_log/$task_name &>/dev/null && [[ $(ls) ]]; then
        ## 寻找所有互助码以及对应的pt_pin
        i=0
        pt_pin_in_log=()
        code=()
        pt_pin_and_code=$(ls -r *.log | xargs awk -v var="的$chinese_name好友互助码" 'BEGIN{FS="[（ ）】]+"; OFS="&"} $3~var {print $2,$4}')
        for line in $pt_pin_and_code; do
            pt_pin_in_log[i]=$(echo $line | awk -F "&" '{print $1}')
            code[i]=$(echo $line | awk -F "&" '{print $2}')
            let i++
        done

        ## 输出互助码
        if [[ ${#code[*]} -gt 0 ]]; then
            for ((m = 0; m < ${#pt_pin[*]}; m++)); do
                tmp_my_code=""
                j=$((m + 1))
                for ((n = 0; n < ${#code[*]}; n++)); do
                    if [[ ${pt_pin[m]} == ${pt_pin_in_log[n]} ]]; then
                        tmp_my_code=${code[n]}
                        break
                    fi
                done
                echo "$config_name$j='$tmp_my_code'"
            done
        else
            echo "## 从日志中未找到任何互助码"
        fi
fi
}

#更新互助码和互助规则
update_help(){
case $UpdateType in
    1)
        if [ "$ps_num" -le $proc_num ] && [ -f $latest_log_path ]; then
            backup_del
            echo -e "\n#【`date +%X`】 开始更新配置文件的互助码和互助规则"
            for ((i = 0; i < ${#name_config[*]}; i++)); do
                help_codes "${name_config[i]}" "${name_chinese[i]}"
                [[ "${name_config[i]}" != "TokenJxnc" ]] && help_rules "${name_config[i]}" "${name_chinese[i]}"
            done
            echo -e "\n#【`date +%X`】 配置文件的互助码和互助规则已完成更新"
        elif [ ! -f $latest_log_path ]; then
            echo -e "\n#【`date +%X`】 日志文件不存在，请检查后重试！"
        fi
        ;;
    2)
        if [ "$ps_num" -le $proc_num ] && [ -f $latest_log_path ]; then
            backup_del
            echo -e "\n#【`date +%X`】 开始更新配置文件的互助码，不更新互助规则"
            for ((i = 0; i < ${#name_config[*]}; i++)); do
                help_codes "${name_config[i]}" "${name_chinese[i]}"
            done
            echo -e "\n#【`date +%X`】 配置文件的互助码已完成更新"
        elif [ ! -f $latest_log_path ]; then
            echo -e "\n#【`date +%X`】 日志文件不存在，请检查后重试！"
        fi
        ;;
    3)
        if [ "$ps_num" -le $proc_num ] && [ -f $latest_log_path ]; then
            backup_del
            echo -e "\n#【`date +%X`】 开始更新配置文件的互助规则，不更新互助码"
            for ((i = 0; i < ${#name_config[*]}; i++)); do
                [[ "${name_config[i]}" != "TokenJxnc" ]] && help_rules "${name_config[i]}" "${name_chinese[i]}"
            done
            echo -e "\n#【`date +%X`】 配置文件的互助规则已完成更新"
        elif [ ! -f $latest_log_path ]; then
            echo -e "\n#【`date +%X`】 日志文件不存在，请检查后重试！"
        fi
        ;;
    *)
        echo -e "\n#【`date +%X`】 您已设置不更新配置文件的互助码和互助规则，跳过更新！"
        ;;
esac
}

check_jd_cookie(){
    local test_connect="$(curl -I -s --connect-timeout 5 https://bean.m.jd.com/bean/signIndex.action -w %{http_code} | tail -n1)"
    local test_jd_cookie="$(curl -s --noproxy "*" "https://bean.m.jd.com/bean/signIndex.action" -H "cookie: $1")"
    if [ "$test_connect" -eq "302" ]; then
        [[ "$test_jd_cookie" ]] && echo "(COOKIE 有效)" || echo "(COOKIE 已失效)"
    else
        echo "(API 连接失败)"
    fi
}

dump_user_info(){
echo -e "\n## 账号用户名及 COOKIES 整理如下："
local envs=$(eval echo "\$JD_COOKIE")
local array=($(echo $envs | sed 's/&/ /g'))
    for ((m = 0; m < ${#pt_pin[*]}; m++)); do
        j=$((m + 1))
        echo -e "## 用户名 $j：${pt_pin[m]} 备注：${remark_name[m]} `check_jd_cookie ${array[m]}`\nCookie$j=\"${array[m]}\""
    done
}

backup_del(){
[[ ! -d $dir_log/.bak_ShareCode ]] && mkdir -p $dir_log/.bak_ShareCode
local bak_ShareCode_full_path_list=$(find $dir_log/.bak_ShareCode/ -name "*.log")
local diff_time
if [[ $BACKUP = "1" ]]; then
    for ((i = 0; i < ${#name_config[*]}; i++)); do
        [[ -f $dir_log/.ShareCode/${name_config[i]}.log ]] && cp $dir_log/.ShareCode/${name_config[i]}.log $dir_log/.bak_ShareCode/${name_config[i]}_`date "+%Y-%m-%d-%H-%M-%S"`.log
    done
fi
if [[ $CLEANBAK = "1" ]]; then
    for log in $bak_ShareCode_full_path_list; do
        local log_date=$(echo $log | awk -F "_" '{print $NF}' | cut -c1-10)
        if [[ $(date +%s -d $log_date 2>/dev/null) ]]; then
            if [[ $is_macos -eq 1 ]]; then
                diff_time=$(($(date +%s) - $(date -j -f "%Y-%m-%d" "$log_date" +%s)))
            else
                diff_time=$(($(date +%s) - $(date +%s -d "$log_date")))
            fi
            [[ $diff_time -gt $(($CLEANBAK_DAYS * 86400)) ]] && rm -vf $log
        fi
    done
fi
}

install_dependencies_normal(){
    for i in $@; do
        case $i in
            canvas)
                cd /ql/scripts
                if [[ "$(echo $(npm ls $i) | grep ERR)" != "" ]]; then
                    npm uninstall $i
                fi
                if [[ "$(npm ls $i)" =~ (empty) ]]; then
                    apk add --no-cache build-base g++ cairo-dev pango-dev giflib-dev && npm i $i --prefix /ql/scripts --build-from-source
                fi
                ;;
            *)
                if [[ "$(npm ls $i)" =~ $i ]]; then
                    npm uninstall $i
                elif [[ "$(echo $(npm ls $i -g) | grep ERR)" != "" ]]; then
                    npm uninstall $i -g
                fi
                if [[ "$(npm ls $i -g)" =~ (empty) ]]; then
                    [[ $i = "typescript" ]] && npm i $i -g --force || npm i $i -g
                fi
                ;;
        esac
    done
}

install_dependencies_force(){
    for i in $@; do
        case $i in
            canvas)
                cd /ql/scripts
                if [[ "$(npm ls $i)" =~ $i && "$(echo $(npm ls $i) | grep ERR)" != "" ]]; then
                    npm uninstall $i
                    rm -rf /ql/scripts/node_modules/$i
                    rm -rf /usr/local/lib/node_modules/lodash/*
                fi
                if [[ "$(npm ls $i)" =~ (empty) ]]; then
                    apk add --no-cache build-base g++ cairo-dev pango-dev giflib-dev && npm i $i --prefix /ql/scripts --build-from-source --force
                fi
                ;;
            *)
                cd /ql/scripts
                if [[ "$(npm ls $i)" =~ $i ]]; then
                    npm uninstall $i
                    rm -rf /ql/scripts/node_modules/$i
                    rm -rf /usr/local/lib/node_modules/lodash/*
                elif [[ "$(npm ls $i -g)" =~ $i && "$(echo $(npm ls $i -g) | grep ERR)" != "" ]]; then
                    npm uninstall $i -g
                    rm -rf /ql/scripts/node_modules/$i
                    rm -rf /usr/local/lib/node_modules/lodash/*
                fi
                if [[ "$(npm ls $i -g)" =~ (empty) ]]; then
                    npm i $i -g --force
                fi
                ;;
        esac
    done
}

install_dependencies_all(){
    install_dependencies_normal $package_name
    for i in $package_name; do
        {install_dependencies_force $i} &
    done
}

kill_proc(){
ps -ef|grep "$1"|grep -Ev "$2"|awk '{print $1}'|xargs kill -9
}

## 执行并写入日志
kill_proc "code.sh" "grep|$$" >/dev/null 2>&1
[[ $FixDependType = "1" ]] && [[ "$ps_num" -le $proc_num ]] && install_dependencies_all >/dev/null 2>&1 &
##latest_log=$(ls -r $dir_code | head -1)
latest_log=$(date "+%Y-%m-%d-%H-%M-%S")
latest_log_path="$dir_code/$latest_log"
make_dir "$dir_code"
ps_num="$(ps | grep code.sh | grep -v grep | wc -l)"
export_all_codes | perl -pe "{s|京东种豆|种豆|; s|crazyJoy任务|疯狂的JOY|}"| tee $latest_log_path
sleep 5
update_help

## 修改curtinlv入会领豆配置文件的参数
[[ -f /ql/repo/curtinlv_JD-Script/OpenCard/OpenCardConfig.ini ]] && sed -i "4c JD_COOKIE = '$(echo $JD_COOKIE | sed "s/&/ /g; s/\S*\(pt_key=\S\+;\)\S*\(pt_pin=\S\+;\)\S*/\1\2/g;" | perl -pe "s| |&|g")'" /ql/repo/curtinlv_JD-Script/OpenCard/OpenCardConfig.ini
