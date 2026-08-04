#!/bin/bash
# set -x
###############################################################################
#
# LICENSED MATERIALS - PROPERTY OF IBM
#
# (C) COPYRIGHT IBM CORP. 2022. ALL RIGHTS RESERVED.
#
# US GOVERNMENT USERS RESTRICTED RIGHTS - USE, DUPLICATION OR
# DISCLOSURE RESTRICTED BY GSA ADP SCHEDULE CONTRACT WITH IBM CORP.
#
###############################################################################
function verify_storage_class_valid(){
  local STORAGE_CLASS_SAMPLE=$TEMP_FOLDER/.storage_sample.yaml
  local STORAGE_CLASS_POD=$TEMP_FOLDER/.storage_pod.yaml
  local sc_name=$1
  local sc_mode=$2
  local sample_pvc_name=$3
  local target_namespace=$4

  if [[ -z "$sc_name" ]]; then
      fail "Storage class name is empty. Please set the storage class name in the property file (CP4BA.SLOW_FILE_STORAGE_CLASSNAME / CP4BA.MEDIUM_FILE_STORAGE_CLASSNAME / CP4BA.FAST_FILE_STORAGE_CLASSNAME / CP4BA.BLOCK_STORAGE_CLASS_NAME)."
      verification_sc_passed="No"
      return 1
  fi

cat << EOF > ${STORAGE_CLASS_SAMPLE}
# YAML template for sample storage class
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    cp4ba: test-only
  name: ${sample_pvc_name}
  namespace: ${target_namespace}
spec:
  accessModes:
  - ${sc_mode}
  resources:
    requests:
      storage: 10Gi
  storageClassName: ${sc_name}
EOF

  # Extract operator image from operator.yaml for WaitForFirstConsumer binding
  local operator_yaml="${CUR_DIR}/../descriptors/operator.yaml"
  local operator_image=""
  
  if [ -f "$operator_yaml" ]; then
      operator_image=$(grep -A 1 "name: folder-prepare-container" "$operator_yaml" | grep "image:" | awk '{print $2}')
  fi
  
  if [ -z "$operator_image" ]; then
      operator_image="icr.io/cpopen/icp4a-operator@sha256:43ab49026c7459d46e0160a4892d82cda5336709c77f258fb288154713af789c"
  fi

cat << EOF > ${STORAGE_CLASS_POD}
# YAML template for test pod to trigger WaitForFirstConsumer binding
---
apiVersion: v1
kind: Pod
metadata:
  labels:
    cp4ba: test-only
  name: ${sample_pvc_name}-pod
  namespace: ${target_namespace}
spec:
  containers:
  - name: test
    image: ${operator_image}
    command: ["sh", "-c", "echo 'Storage test successful' && sleep 10"]
    volumeMounts:
    - name: test-volume
      mountPath: /data
  volumes:
  - name: test-volume
    persistentVolumeClaim:
      claimName: ${sample_pvc_name}
  restartPolicy: Never
EOF
  
    # Apply PVC
    kubectl apply -f ${STORAGE_CLASS_SAMPLE} >/dev/null 2>&1
    
    # Check storage class binding mode
    local binding_mode=$(kubectl get storageclass ${sc_name} -o jsonpath='{.volumeBindingMode}' 2>/dev/null)
    
    # Set timeout based on storage type (filestore needs more time)
    # aks requires timeout to be increased. So took from 12 to 20 tries and extended timeout from 36 to 60.
    local TIMEOUT=20
    local EXTENDED_TIMEOUT=60
    
    # Detect if this is a filestore/NFS type storage (typically slower)
    local provisioner=$(kubectl get storageclass ${sc_name} -o jsonpath='{.provisioner}' 2>/dev/null)
    if [[ "$provisioner" == *"nfs"* ]] || [[ "$provisioner" == *"filestore"* ]] || [[ "$provisioner" == *"efs"* ]] || [[ "$provisioner" == *"azurefile"* ]]; then
        TIMEOUT=$EXTENDED_TIMEOUT
        info "Detected file storage provisioner (${provisioner}), using extended timeout of ${TIMEOUT} attempts (3 minutes)"
    fi
    
    ATTEMPTS=0
    printf "\n"
    info "Checking the storage class: \"${sc_name}\" (binding mode: ${binding_mode:-Immediate})..."
    
    # If binding mode is WaitForFirstConsumer, we need to create a pod to trigger binding
    if [[ "$binding_mode" == "WaitForFirstConsumer" ]]; then
        info "Storage class uses WaitForFirstConsumer binding mode, creating test pod to trigger binding..."
        
        # Wait a moment for PVC to be created
        sleep 2
        
        # Create pod to trigger binding
        kubectl apply -f ${STORAGE_CLASS_POD} >/dev/null 2>&1
        
        # Wait for PVC to bind (triggered by pod creation)
        until kubectl get pvc ${sample_pvc_name} -n ${target_namespace} -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Bound" || [ $ATTEMPTS -eq $TIMEOUT ]; do
            ATTEMPTS=$((ATTEMPTS + 1))
            local pvc_status=$(kubectl get pvc ${sample_pvc_name} -n ${target_namespace} -o jsonpath='{.status.phase}' 2>/dev/null)
            echo -e "...... (attempt $ATTEMPTS/$TIMEOUT, PVC status: ${pvc_status:-Unknown})"
            sleep 5
            
            if [ $ATTEMPTS -eq $TIMEOUT ] ; then
                warning "PVC did not bind within expected time"
                kubectl describe pvc ${sample_pvc_name} -n ${target_namespace} 2>/dev/null | tail -20
                fail "Failed to allocate the persistent volumes using storage class: \"${sc_name}\"!"
                verification_sc_passed="No"
            fi
        done
        
        # Clean up pod
        kubectl delete -f ${STORAGE_CLASS_POD} --grace-period=0 --force >/dev/null 2>&1
        
    else
        # Immediate binding mode - PVC should bind without a pod
        until kubectl get pvc ${sample_pvc_name} -n ${target_namespace} -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Bound" || [ $ATTEMPTS -eq $TIMEOUT ]; do
            ATTEMPTS=$((ATTEMPTS + 1))
            local pvc_status=$(kubectl get pvc ${sample_pvc_name} -n ${target_namespace} -o jsonpath='{.status.phase}' 2>/dev/null)
            echo -e "...... (attempt $ATTEMPTS/$TIMEOUT, PVC status: ${pvc_status:-Unknown})"
            sleep 5
            
            if [ $ATTEMPTS -eq $TIMEOUT ] ; then
                warning "PVC did not bind within expected time"
                kubectl describe pvc ${sample_pvc_name} -n ${target_namespace} 2>/dev/null | tail -20
                fail "Failed to allocate the persistent volumes using storage class: \"${sc_name}\"!"
                verification_sc_passed="No"
            fi
        done
    fi
    
    if [ $ATTEMPTS -lt $TIMEOUT ] ; then
            success "Verification storage class: \"${sc_name}\", PASSED!"
            
            # Clean up resources
            kubectl delete -f ${STORAGE_CLASS_POD} --grace-period=0 --force >/dev/null 2>&1
            kubectl delete -f ${STORAGE_CLASS_SAMPLE} >/dev/null 2>&1
            
            # Wait for PVC to be fully deleted
            local delete_attempts=0
            while kubectl get pvc ${sample_pvc_name} -n ${target_namespace} >/dev/null 2>&1 && [ $delete_attempts -lt 12 ]; do
                delete_attempts=$((delete_attempts + 1))
                sleep 2
            done
            
            verification_sc_passed="Yes"
            printf "\n"
    fi

    rm -rf ${STORAGE_CLASS_SAMPLE} >/dev/null 2>&1
    rm -rf ${STORAGE_CLASS_POD} >/dev/null 2>&1
}

# verify ldap connection
function verify_ldap_connection(){
  local LDAP_TEST_JAR_PATH=${CUR_DIR}/helper/verification/ldap
  local ldap_server=$1
  local ldap_port=$2
  local ldap_basedn=$3
  local ldap_binddn=$4
  local ldap_binddn_pwd=$5
  local ldap_ssl=$6
  local ldap_group_basedn=$7
  local ldap_user_filter=$8
  local ldap_group_filter=$9
  local ldap_user_password_list=${10}
  local ldap_group_list=${11}


  if [[ $ldap_ssl == "true" || $ldap_ssl == "yes" || $ldap_ssl == "y" ]]; then
    tmp_cert_folder="$(prop_ldap_property_file LDAP_SSL_CERT_FILE_FOLDER)"
    if [[ ! -f "${tmp_cert_folder}/ldap-cert.crt" ]]; then
      fail "Not found required certificat file \"ldap-cert.crt\" under \"$tmp_cert_folder\", exit..."
      exit 1
    fi
    rm -rf /tmp/ldap.der 2>&1 </dev/null
    rm -rf /tmp/ldap-truststore.jks 2>&1 </dev/null
    #  add keytool to system PATH.
    sudo -s export PATH="/opt/ibm/java/jre/bin/:$PATH"; export PATH="/opt/ibm/java/jre/bin/:$PATH"; echo "PATH=$PATH:/opt/ibm/java/jre/bin/" >> ~/.bashrc; source ~/.bashrc

    openssl x509 -outform der -in $tmp_cert_folder/ldap-cert.crt -out /tmp/ldap.der 2>&1 </dev/null
    keytool -import -alias cp4baLdapCerts -keystore /tmp/ldap-truststore.jks -file /tmp/ldap.der -storepass changeit -storetype JKS -noprompt 2>&1 </dev/null
    msg "Checking connection for LDAP server \"$ldap_server\" using Bind DN \"$ldap_binddn\".."

    java_command_string="java -Djavax.net.ssl.trustStore=/tmp/ldap-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit -jar ${LDAP_TEST_JAR_PATH}/LdapTest.jar -u 'ldaps://$ldap_server:$ldap_port' -b '$ldap_basedn' -D '$ldap_binddn' -w '$ldap_binddn_pwd' -additionalvalidation -gdn '$ldap_group_basedn' -upl '$ldap_user_password_list' -gl '$ldap_group_list' -uf '$ldap_user_filter' -gf '$ldap_group_filter' 2>&1"
    output=$(eval "$java_command_string" | tr -d '\0' )
    retVal_verify_ldap_tmp=$?
    if [[ "$output" == *"Error while binding to LDAP"* ]]; then
      warning "Execute: java -Djavax.net.ssl.trustStore=/tmp/ldap-truststore.jks -Djavax.net.ssl.trustStorePassword=changeit -jar ${LDAP_TEST_JAR_PATH}/LdapTest.jar -u \"ldaps://$ldap_server:$ldap_port\" -b \"$ldap_basedn\" -D \"$ldap_binddn\" -w \"******\"" && \
      fail "Unable to connect to LDAP server \"$ldap_server\" using Bind DN \"$ldap_binddn\", please check configuration in ldap property again."
    else
      # Moving all additional validation checks to be displayed only if we get a successful connection
      #For https://jsw.ibm.com/browse/DBACLD-158315
      success "Connected to LDAP \"$ldap_server\" using BindDN:\"$ldap_binddn\" successfuly, PASSED!"
      printf "\n"
      connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
      echo "Latency: $connection_time ms"
      # Check if elapsed time is greater than 10 ms using awk
      if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
        echo "The latency is less than 10ms, which is acceptable performance for a simple LDAP operation."
      elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
        echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple LDAP operation, but the service is still accessible."
      elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
        echo "The latency exceeds 30ms for a simple LDAP operation, which indicates potential for failures."
      fi
      # Extract everything from "LDAP Users Summary" until "Total time taken"
      # /LDAP Users Summary/ {flag=1} starts printing everything from LDAP Users Summary and /Total time taken/ {flag=0} stops printing when Total time taken is found
      # https://jsw.ibm.com/browse/DBACLD-159190
      # showing the group summary only if grouplist passed to the jar is not empty, One such use case is for an ADS only deployment that requires no ldap group is required to be specified in the property file
      if [[ ${#ldap_group_list} -eq 0 ]]; then
        ldap_validation_table=$(echo "$output" | awk '/LDAP Users Summary/ {flag=1} /LDAP Groups Summary/ {flag=0} flag')
      else
        ldap_validation_table=$(echo "$output" | awk '/LDAP Users Summary/ {flag=1} /Total time taken/ {flag=0} flag')
      fi
      echo "$ldap_validation_table"
      printf "\n"
    fi
  else
    msg "Checking connection for LDAP server \"$ldap_server\" using Bind DN \"$ldap_binddn\".."
    java_command_string="java -jar ${LDAP_TEST_JAR_PATH}/LdapTest.jar -u 'ldap://$ldap_server:$ldap_port' -b '$ldap_basedn' -D '$ldap_binddn' -w '$ldap_binddn_pwd' -additionalvalidation -gdn '$ldap_group_basedn' -upl '$ldap_user_password_list' -gl '$ldap_group_list' -uf '$ldap_user_filter' -gf '$ldap_group_filter' 2>&1"
    output=$(eval "$java_command_string" | tr -d '\0' )
    retVal_verify_ldap_tmp=$?
    if [[ "$output" == *"Error while binding to LDAP"* ]]; then
      warning "Execution: java -jar ${LDAP_TEST_JAR_PATH}/LdapTest.jar -u \"ldap://$ldap_server:$ldap_port\" -b \"$ldap_basedn\" -D \"$ldap_binddn\" -w \"******\"" && \
      fail "Unable to connect to LDAP server \"$ldap_server\" using Bind DN \"$ldap_binddn\", please check configuration in ldap property again."
    else
      # Moving all additional validation checks to be displayed only if we get a successful connection
      #For https://jsw.ibm.com/browse/DBACLD-158315
      success "Connected to LDAP \"$ldap_server\" using BindDN:\"$ldap_binddn\" successfuly, PASSED!"
      printf "\n"
      connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
      echo "Latency: $connection_time ms"
      # Check if elapsed time is greater than 10 ms using awk
      if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
        echo "The latency is less than 10ms, which is acceptable performance for a simple LDAP operation."
      elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
        echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple LDAP operation, but the service is still accessible."
      elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
        echo "The latency exceeds 30ms for a simple LDAP operation, which indicates potential for failures."
      fi
      # Extract everything from "LDAP Users Summary" until "Total time taken"
      # /LDAP Users Summary/ {flag=1} starts printing everything from LDAP Users Summary and /Total time taken/ {flag=0} stops printing when Total time taken is found
      # https://jsw.ibm.com/browse/DBACLD-159190
      # showing the group summary only if grouplist passed to the jar is not empty, One such use case is for an ADS only deployment that requires no ldap group is required to be specified in the property file
      if [[ ${#ldap_group_list} -eq 0 ]]; then
        ldap_validation_table=$(echo "$output" | awk '/LDAP Users Summary/ {flag=1} /LDAP Groups Summary/ {flag=0} flag')
      else
        ldap_validation_table=$(echo "$output" | awk '/LDAP Users Summary/ {flag=1} /Total time taken/ {flag=0} flag')
      fi
      echo "$ldap_validation_table"
      printf "\n" 
    fi
  fi 
}

# verification db connection

function verify_db_connection(){
  local DB_JDBC_NAME=${JDBC_DRIVER_DIR}/$DB_TYPE
  local DB_CONNECTION_JAR_PATH=${CUR_DIR}/helper/verification/$DB_TYPE
  local LDAP_TEST_JAR_PATH=${CUR_DIR}/helper/verification/ldap
  
  if [[ $DB_TYPE == "oracle" ]]; then
    local dbuser=$1
    local dbuserpwd=$2
    local db_server_list_element=$3
  else
    local dbname=$1
    local dbuser=$2
    local dbuserpwd=$3
    local db_server_list_element=$4
    local base_dbname=$(prop_db_name_user_property_file ADP_BASE_DB_NAME)
    local proj_dbname=$(prop_db_name_user_property_file ADP_PROJECT_DB_NAME)
    IFS=',' read -ra proj_dbname_array <<< "$proj_dbname"
    # postgresql only support lower-case db name
    if [[ "$DB_TYPE" == "postgresql" && "$dbname" != "$base_dbname" ]]; then
      match_found=false
      for proj_dbname in "${proj_dbname_array[@]}"; do
        if [[ "$dbname" == "$proj_dbname" ]]; then
          match_found=true
          break
        fi
      done
      if [[ "$match_found" == false ]]; then
        dbname=$(echo "$dbname" | tr '[:upper:]' '[:lower:]')
      fi
    fi
  fi
  
  retVal_verify_db=0

  if [[ $DB_TYPE == "oracle" ]]; then
      printf "\n"
      info "Checking connection for $DB_TYPE database \"${dbuser}\" belongs to database instance \"${db_server_list_element}\" which defined in <DB_SERVER_LIST>...."

      oracle_url=$(prop_db_oracle_server_property_file  $db_server_list_element.ORACLE_JDBC_URL)
      oracle_url=$(sed -e 's/^"//' -e 's/"$//' <<<"$oracle_url")
  else
      printf "\n"
      info "Checking connection for $DB_TYPE database \"${dbname}\" belongs to database server \"${db_server_list_element}\" which defined in <DB_SERVER_LIST>...."

      dbserver=$(prop_db_server_property_file $db_server_list_element.DATABASE_SERVERNAME)
      dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbserver")

      dbport=$(prop_db_server_property_file $db_server_list_element.DATABASE_PORT)
      dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbport")
  fi
  tmp_dbssl_flag="$(prop_db_server_property_file $db_server_list_element.DATABASE_SSL_ENABLE)"
  tmp_dbssl_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbssl_flag")
  tmp_dbssl_flag=$(echo $tmp_dbssl_flag| tr '[:upper:]' '[:lower:]')

  if [[ $tmp_dbssl_flag == "true" || $tmp_dbssl_flag == "yes" || $tmp_dbssl_flag == "y" ]]; then
    dbcafolder="$(prop_db_server_property_file $db_server_list_element.DATABASE_SSL_CERT_FILE_FOLDER)"
    dbcafolder=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbcafolder")

    # check certification existing or not
    if [[ $DB_TYPE == "oracle" ]]; then
      if [[ ! -f "${dbcafolder}/db-cert.crt" ]]; then
        fail "Not found required server certificat file \"db-cert.crt\" under \"$dbcafolder\" for $DB_TYPE database instance \"$dbuser\", exit..."
        exit 1
      fi
    elif [[ $DB_TYPE == "db2" || $DB_TYPE == "db2HADR" || $DB_TYPE == "sqlserver" || $DB_TYPE == "azuresqlmi" ]]; then
      if [[ ! -f "${dbcafolder}/db-cert.crt" ]]; then
        fail "Not found required server certificat file \"db-cert.crt\" under \"$dbcafolder\" for $DB_TYPE database server \"$dbserver\", exit..."
        exit 1
      fi
    elif [[ $DB_TYPE == "postgresql" ]]; then
        tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_db_server_property_file $db_server_list_element.POSTGRESQL_SSL_CLIENT_SERVER)")
        tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
        if [[ $tmp_flag == "no" || $tmp_flag == "false" || $tmp_flag == "" || -z $tmp_flag ]]; then
          if [[ ! -f "${dbcafolder}/db-cert.crt" ]]; then
            fail "Not found required server certificat file \"db-cert.crt\" under \"$dbcafolder\" for $DB_TYPE database server \"$dbserver\", exit..."
            exit 1
          fi
        elif [[ $tmp_flag == "yes" || $tmp_flag == "true" || $tmp_flag == "y" ]]; then
          if [[ ! -f "${dbcafolder}/root.crt" ]]; then
            fail "Not found required server certificate file \"root.crt\" under \"$dbcafolder\" for $DB_TYPE database server \"$dbserver\", exit..."
            exit 1
          fi
          if [[ ! -f "${dbcafolder}/client.crt" ]]; then
            fail "Not found required client certificat file \"client.crt\" for under \"$dbcafolder\" for $DB_TYPE database server \"$dbserver\", exit..."
            exit 1
          fi
          if [[ ! -f "${dbcafolder}/client.key" ]]; then
            fail "Not found required client key file \"client.key\" under \"$dbcafolder\" for $DB_TYPE database server \"$dbserver\", exit..."
            exit 1
          fi
        fi
    fi
    ## DB SSL enable
    while true; do
        case $DB_TYPE in
          "db2")                                                                                   # -h {{ db2_server }} -p {{ db2_port }} -db {{ db2_dbname }} -u {{ db2_user }} -pwd {{ db2_pwd }} -ssl -ca {{ db2_cafile }}
              output=$(java -Duser.language=en -Duser.country=US -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/db2jcc4.jar:${DB_CONNECTION_JAR_PATH}/DB2JDBCConnection.jar" DB2Connection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -ssl -ca $dbcafolder/db-cert.crt 2>&1)
              retVal_verify_db_tmp=$?
              connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
              if [[ ! -z $connection_time ]]; then
                echo "Latency: $connection_time ms"
                # Check if elapsed time is greater than 10 ms using awk
                if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
                  echo "The latency is less than 10ms, which is acceptable performance for a simple DB operation."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
                  echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple DB operation, but the service is still accessible."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
                  echo "The latency exceeds 30ms for a simple DB operation, which indicates potential for failures."
                fi
              fi
              [[ retVal_verify_db_tmp -ne 0 ]] && \
              warning "Execute: java -Duser.language=en -Duser.country=US -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/db2jcc4.jar:${DB_CONNECTION_JAR_PATH}/DB2JDBCConnection.jar\" DB2Connection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -ssl -ca $dbcafolder/db-cert.crt" && \
              fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check configuration again."
              [[ retVal_verify_db_tmp -eq 0 ]] && \
              success "Checked DB connection for \"$dbname\" on database server \"$dbserver\", PASSED!"
              break
              ;;
          "oracle")                                                                                                                                 # -url "{{ oracle_url }}" -u {{ oracle_user }} -pwd {{ oracle_password_decoded }} -ssl -trustorefile {{trustorefile}} -trustoretype {{trustoretype}} -trustorePwd {{trustorePwd}}
              TRUSTSTORE_FOLDER="/tmp/${DB_TYPE}_db_truststore/${db_server_list_element}"
              rm -rf $TRUSTSTORE_FOLDER 2>&1 </dev/null
              mkdir -p $TRUSTSTORE_FOLDER 2>&1 </dev/null
              #  add keytool to system PATH.
              sudo -s export PATH="/opt/ibm/java/jre/bin/:$PATH"; export PATH="/opt/ibm/java/jre/bin/:$PATH"; echo "PATH=$PATH:/opt/ibm/java/jre/bin/" >> ~/.bashrc; source ~/.bashrc

              openssl x509 -outform der -in $dbcafolder/db-cert.crt -out $TRUSTSTORE_FOLDER/oracle-db-cert.der 2>&1 </dev/null
              keytool -import -alias cp4baOraleCerts -keystore $TRUSTSTORE_FOLDER/oracle-db-truststore.p12 -file $TRUSTSTORE_FOLDER/oracle-db-cert.der -storepass changeit -storetype PKCS12 -noprompt 2>&1 </dev/null

              output=$(java -Duser.language=en -Duser.country=US -cp "${DB_JDBC_NAME}/ojdbc8.jar:${DB_CONNECTION_JAR_PATH}/OracleJDBCConnection.jar" OracleConnection -url "$oracle_url" -u $dbuser -pwd $dbuserpwd -ssl -trustorefile $TRUSTSTORE_FOLDER/oracle-db-truststore.p12 -trustoretype "PKCS12" -trustorePwd "changeit" 2>&1)
              retVal_verify_db_tmp=$?
              connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
              if [[ ! -z $connection_time ]]; then
                echo "Latency: $connection_time ms"
                # Check if elapsed time is greater than 10 ms using awk
                if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
                  echo "The latency is less than 10ms, which is acceptable performance for a simple DB operation."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
                  echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple DB operation, but the service is still accessible."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
                  echo "The latency exceeds 30ms for a simple DB operation, which indicates potential for failures."
                fi
              fi
              [[ retVal_verify_db_tmp -ne 0 ]] && \
              warning "Execute: java -Duser.language=en -Duser.country=US -cp \"${DB_JDBC_NAME}/ojdbc8.jar:${DB_CONNECTION_JAR_PATH}/OracleJDBCConnection.jar\" OracleConnection -url \"$oracle_url\" -u $dbuser -pwd ****** -ssl -trustorefile $TRUSTSTORE_FOLDER/oracle-db-truststore.p12 -trustoretype \"PKCS12\" -trustorePwd \"changeit\"" && \
              fail "Unable to connect to database \"$dbuser\" using JDBC URL \"$oracle_url\", please check configuration again."
              [[ retVal_verify_db_tmp -eq 0 ]] && \
              success "Checked DB connection for \"$dbuser\" using JDBC URL \"$oracle_url\", PASSED!"
              break
              ;;
          "sqlserver"|"azuresqlmi")                                                                                                          # SQLConnection -h {{ database_servername }} -p {{ database_port }} -d {{ database_name }} -u {{ sqlserver_user }} -pwd {{ sqlserver_password_decoded }} -ssl '{{ ssl_connection_str }}'
              TRUSTSTORE_FOLDER="/tmp/${DB_TYPE}_db_truststore/${db_server_list_element}"
              rm -rf $TRUSTSTORE_FOLDER 2>&1 </dev/null
              mkdir -p $TRUSTSTORE_FOLDER 2>&1 </dev/null
              #  add keytool to system PATH.
              sudo -s export PATH="/opt/ibm/java/jre/bin/:$PATH"; export PATH="/opt/ibm/java/jre/bin/:$PATH"; echo "PATH=$PATH:/opt/ibm/java/jre/bin/" >> ~/.bashrc; source ~/.bashrc

              openssl x509 -outform der -in $dbcafolder/db-cert.crt -out $TRUSTSTORE_FOLDER/sqlserver-db-cert.der 2>&1 </dev/null
              keytool -import -alias cp4baSQLServerCerts -keystore $TRUSTSTORE_FOLDER/sqlserver-db-truststore.p12 -file $TRUSTSTORE_FOLDER/sqlserver-db-cert.der -storepass changeit -storetype PKCS12 -noprompt 2>&1 </dev/null
                                                                                                                        # ssl_connection_str: "encrypt=true;trustServerCertificate=false;trustStore={{ban_cert_dir}}/ibm_customBANTrustStore.p12;trustStorePassword={{ ban_keystore_decoded_pwd|first if '{xor}' in ban_keystore_password else ban_keystore_password }}"
              SSL_CONNECTION_STR="fips=$fips_flag;encrypt=true;trustServerCertificate=false;trustStore=${TRUSTSTORE_FOLDER}/sqlserver-db-truststore.p12;trustStorePassword=changeit"
              output=$(java -Duser.language=en -Duser.country=US -cp "${DB_JDBC_NAME}/mssql-jdbc.jre11.jar:${DB_CONNECTION_JAR_PATH}/SQLJDBCConnection.jar" SQLConnection -h $dbserver -p $dbport -d $dbname -u $dbuser -pwd $dbuserpwd -ssl "$SSL_CONNECTION_STR" 2>&1)
              retVal_verify_db_tmp=$?
              connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
              if [[ ! -z $connection_time ]]; then
                echo "Latency: $connection_time ms"
                # Check if elapsed time is greater than 10 ms using awk
                if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
                  echo "The latency is less than 10ms, which is acceptable performance for a simple DB operation."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
                  echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple DB operation, but the service is still accessible."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
                  echo "The latency exceeds 30ms for a simple DB operation, which indicates potential for failures."
                fi
              fi

              [[ retVal_verify_db_tmp -ne 0 ]] && \
              warning "Execute: java -Duser.language=en -Duser.country=US -cp \"${DB_JDBC_NAME}/mssql-jdbc.jre11.jar:${DB_CONNECTION_JAR_PATH}/SQLJDBCConnection.jar\" SQLConnection -h $dbserver -p $dbport -d $dbname -u $dbuser -pwd ****** -ssl \"$SSL_CONNECTION_STR\"" && \
              fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check configuration again."
              [[ retVal_verify_db_tmp -eq 0 ]] && \
              success "Checked DB connection for \"$dbname\" on database server \"$dbserver\", PASSED!"
              break
              ;;
          "postgresql")
              tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_db_server_property_file $db_server_list_element.POSTGRESQL_SSL_CLIENT_SERVER)")
              tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
              if [[ $tmp_flag == "no" || $tmp_flag == "false" || $tmp_flag == "" || -z $tmp_flag ]]; then
                postgres_cafile="${dbcafolder}/db-cert.crt"
                output=$(java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.13.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode require -ca $postgres_cafile 2>&1)
                retVal_verify_db_tmp=$?
                connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
                if [[ ! -z $connection_time ]]; then
                  echo "Latency: $connection_time ms"
                  # Check if elapsed time is greater than 10 ms using awk
                  if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
                    echo "The latency is less than 10ms, which is acceptable performance for a simple DB operation."
                  elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
                    echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple DB operation, but the service is still accessible."
                  elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
                    echo "The latency exceeds 30ms for a simple DB operation, which indicates potential for failures."
                  fi
                fi

                [[ retVal_verify_db_tmp -ne 0 ]] && \
                warning "Execute: java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.13.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode require -ca $postgres_cafile" && \
                fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check configuration again."
                [[ retVal_verify_db_tmp -eq 0 ]] && \
                success "Checked DB connection for \"$dbname\" on database server \"$dbserver\", PASSED!"
              elif [[ $tmp_flag == "yes" || $tmp_flag == "true" || $tmp_flag == "y" ]]; then
                postgres_cafile="${dbcafolder}/root.crt"
                postgres_clientkeyfile="${dbcafolder}/client.key"
                postgres_clientcertfile="${dbcafolder}/client.crt"

                rm -rf ${dbcafolder}/clientkey.pk8 2>&1 </dev/null
                openssl pkcs8 -topk8 -outform DER -in $postgres_clientkeyfile -out ${dbcafolder}/clientkey.pk8 -nocrypt 2>&1 </dev/null
                dbuserpwd="changit" # client auth does not need dbuserpwd
                output=$(java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.13.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${dbcafolder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
                retVal_verify_db_tmp=$?
                connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
                if [[ ! -z $connection_time ]]; then
                  echo "Latency: $connection_time ms"
                  # Check if elapsed time is greater than 10 ms using awk
                  if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
                    echo "The latency is less than 10ms, which is acceptable performance for a simple DB operation."
                  elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
                    echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple DB operation, but the service is still accessible."
                  elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
                    echo "The latency exceeds 30ms for a simple DB operation, which indicates potential for failures."
                  fi
                fi

                [[ retVal_verify_db_tmp -ne 0 ]] && \
                warning "Execute: java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.13.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${dbcafolder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
                fail "Unable to connect to database \"$dbname\" on database server \"$dbserver\", please check configuration again."
                [[ retVal_verify_db_tmp -eq 0 ]] && \
                success "Checked DB connection for \"$dbname\" on database server \"$dbserver\", PASSED!"
              fi                                                                                                                                                                                  # -h {{ postgres_host }} -p {{ postgres_port }} -db {{ postgres_db }} -u {{ postgresql_server_user }} -pwd {{ postgres_pwd }} -sslmode require -ca {{ postgres_cafile}}              
              break
              ;;
        esac
    done  
  else
    ## DB SSL disabled
    while true; do
        case $DB_TYPE in
          "db2")                                                                                                                                                   # -h {{ db2_server }} -p {{ db2_port }} -db {{ db2_dbname }} -u {{ db2_user }} -pwd {{ db2_pwd }} -ssl -ca {{ db2_cafile }}
              output=$(java -Duser.language=en -Duser.country=US -cp "${DB_JDBC_NAME}/db2jcc4.jar:${DB_CONNECTION_JAR_PATH}/DB2JDBCConnection.jar" DB2Connection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd 2>&1)
              retVal_verify_db_tmp=$?
              connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
              if [[ ! -z $connection_time ]]; then
                echo "Latency: $connection_time ms"
                # Check if elapsed time is greater than 10 ms using awk
                if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
                  echo "The latency is less than 10ms, which is acceptable performance for a simple DB operation."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
                  echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple DB operation, but the service is still accessible."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
                  echo "The latency exceeds 30ms for a simple DB operation, which indicates potential for failures."
                fi
              fi

              [[ retVal_verify_db_tmp -ne 0 ]] && \
              warning "Execute: java -Duser.language=en -Duser.country=US -cp \"${DB_JDBC_NAME}/db2jcc4.jar:${DB_CONNECTION_JAR_PATH}/DB2JDBCConnection.jar\" DB2Connection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ******" && \
              fail "Unable to connect to database \"$dbname\" on database host server \"$dbserver\", please check configuration again."
              [[ retVal_verify_db_tmp -eq 0 ]] && \
              success "Checked DB connection for \"$dbname\" on database host server \"$dbserver\", PASSED!"
              break
              ;;
          "oracle")                                                                                                                                 # -url "{{ oracle_url }}" -u {{ oracle_user }} -pwd {{ oracle_password_decoded }} -ssl -trustorefile {{trustorefile}} -trustoretype {{trustoretype}} -trustorePwd {{trustorePwd}}
              output=$(java -Duser.language=en -Duser.country=US -cp "${DB_JDBC_NAME}/ojdbc8.jar:${DB_CONNECTION_JAR_PATH}/OracleJDBCConnection.jar" OracleConnection -url "$oracle_url" -u $dbuser -pwd $dbuserpwd 2>&1)
              retVal_verify_db_tmp=$?
              connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
              if [[ ! -z $connection_time ]]; then
                echo "Latency: $connection_time ms"
                # Check if elapsed time is greater than 10 ms using awk
                if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
                  echo "The latency is less than 10ms, which is acceptable performance for a simple DB operation."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
                  echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple DB operation, but the service is still accessible."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
                  echo "The latency exceeds 30ms for a simple DB operation, which indicates potential for failures."
                fi
              fi

              [[ retVal_verify_db_tmp -ne 0 ]] && \
              warning "Execute: java -Duser.language=en -Duser.country=US -cp \"${DB_JDBC_NAME}/ojdbc8.jar:${DB_CONNECTION_JAR_PATH}/OracleJDBCConnection.jar\" OracleConnection -url \"$oracle_url\" -u $dbuser -pwd ******" && \
              echo -e  "\x1B[1;31mUnable to connect to database \"$dbuser\" using JDBC URL \"$oracle_url\", please check configuration again.\x1B[0m"
              [[ retVal_verify_db_tmp -eq 0 ]] && \
              success "Checked DB connection for \"$dbuser\" using JDBC URL \"$oracle_url\", PASSED!"
              break
              ;;
          "sqlserver"|"azuresqlmi")                                                                                                          # SQLConnection -h {{ database_servername }} -p {{ database_port }} -d {{ database_name }} -u {{ sqlserver_user }} -pwd {{ sqlserver_password_decoded }} -ssl 'encrypt=false'
              output=$(java -Duser.language=en -Duser.country=US -cp "${DB_JDBC_NAME}/mssql-jdbc.jre11.jar:${DB_CONNECTION_JAR_PATH}/SQLJDBCConnection.jar" SQLConnection -h $dbserver -p $dbport -d $dbname -u $dbuser -pwd $dbuserpwd -ssl 'encrypt=false' 2>&1)
              retVal_verify_db_tmp=$?
              connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
              if [[ ! -z $connection_time ]]; then
                echo "Latency: $connection_time ms"
                # Check if elapsed time is greater than 10 ms using awk
                if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
                  echo "The latency is less than 10ms, which is acceptable performance for a simple DB operation."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
                  echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple DB operation, but the service is still accessible."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
                  echo "The latency exceeds 30ms for a simple DB operation, which indicates potential for failures."
                fi
              fi
              [[ retVal_verify_db_tmp -ne 0 ]] && \
              warning "Execute: java -Duser.language=en -Duser.country=US -cp \"${DB_JDBC_NAME}/mssql-jdbc.jre11.jar:${DB_CONNECTION_JAR_PATH}/SQLJDBCConnection.jar\" SQLConnection -h $dbserver -p $dbport -d $dbname -u $dbuser -pwd ****** -ssl 'encrypt=false'" && \
              fail "Unable to connect to database \"$dbname\" on database host server \"$dbserver\", please check configuration again."
              [[ retVal_verify_db_tmp -eq 0 ]] && \
              success "Checked DB connection for \"$dbname\" on database host server \"$dbserver\", PASSED!"
              break
              ;;
          "postgresql")                                                                                                                                                                                    # -h {{ postgres_host }} -p {{ postgres_port }} -db {{ postgres_db }} -u {{ postgresql_server_user }} -pwd {{ postgres_pwd }} -sslmode require -ca {{ postgres_cafile}}
              output=$(java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -cp "${DB_JDBC_NAME}/postgresql-42.7.13.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode disable 2>&1)
              retVal_verify_db_tmp=$?
              connection_time=$(echo $output | awk -F 'Round Trip time: ' '{print $2}' | awk '{print $1}')
              if [[ ! -z $connection_time ]]; then
                echo "Latency: $connection_time ms"
                # Check if elapsed time is greater than 10 ms using awk
                if [[ $(awk 'BEGIN { print ("'$connection_time'" < 10) }') -eq 1 ]]; then
                  echo "The latency is less than 10ms, which is acceptable performance for a simple DB operation."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 10 && "'$connection_time'" < 30) }') -eq 1 ]]; then
                  echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple DB operation, but the service is still accessible."
                elif [[ $(awk 'BEGIN { print ("'$connection_time'" > 30) }') -eq 1 ]]; then
                  echo "The latency exceeds 30ms for a simple DB operation, which indicates potential for failures."
                fi
              fi
              [[ retVal_verify_db_tmp -ne 0 ]] && \
              warning "Execute: java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -cp \"${DB_JDBC_NAME}/postgresql-42.7.13.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode disable" && \
              fail "Unable to connect to database \"$dbname\" on database host server \"$dbserver\", please check configuration again."
              [[ retVal_verify_db_tmp -eq 0 ]] && \
              success "Checked DB connection for \"$dbname\" on database host server \"$dbserver\", PASSED!"
              break
              ;;
        esac
    done
  fi 
}
