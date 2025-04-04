#!/bin/bash

# สคริปต์สำหรับสร้าง Keystore จาก certificate และ private key
# เหมาะสำหรับใช้กับ Tomcat

# กำหนดสีสำหรับแสดงผล
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ตรวจสอบการติดตั้ง keytool และ openssl
if ! command -v keytool &> /dev/null; then
    echo -e "${RED}❌ Error: keytool ไม่ได้ติดตั้ง กรุณาติดตั้ง Java JDK/JRE ก่อน${NC}"
    exit 1
fi

if ! command -v openssl &> /dev/null; then
    echo -e "${RED}❌ Error: openssl ไม่ได้ติดตั้ง กรุณาติดตั้ง OpenSSL ก่อน${NC}"
    exit 1
fi

# ฟังก์ชั่นแสดงวิธีใช้งาน
usage() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║            ${YELLOW}เครื่องมือสร้าง Keystore สำหรับ Tomcat${BLUE}               ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}วิธีใช้งาน:${NC} $0 -c <certificate> -i <intermediate_chain> -k <private_key> [-p <keystore_password>] [-a <alias>] [-o <output_keystore>] [-f <format>]"
    echo ""
    echo -e "${YELLOW}พารามิเตอร์ที่จำเป็น:${NC}"
    echo -e "  ${GREEN}-c${NC}   ไฟล์ certificate (เช่น website.crt)"
    echo -e "  ${GREEN}-i${NC}   ไฟล์ intermediate certificate chain (เช่น ca-chain.crt)"
    echo -e "  ${GREEN}-k${NC}   ไฟล์ private key (เช่น website.key)"
    echo ""
    echo -e "${YELLOW}พารามิเตอร์ทางเลือก:${NC}"
    echo -e "  ${GREEN}-p${NC}   รหัสผ่านสำหรับ keystore (ค่าเริ่มต้น: xxxxxxxx)"
    echo -e "  ${GREEN}-a${NC}   alias ที่ใช้ในการเก็บ certificate ใน keystore (ค่าเริ่มต้น: demo)"
    echo -e "  ${GREEN}-o${NC}   ชื่อไฟล์ output keystore (ค่าเริ่มต้น: demo.jks หรือ demo.p12)"
    echo -e "  ${GREEN}-f${NC}   รูปแบบของ keystore: JKS หรือ PKCS12 (ค่าเริ่มต้น: JKS)"
    echo ""
    echo -e "${YELLOW}ตัวอย่าง:${NC}"
    echo -e "  $0 -c website.crt -i chain.crt -k website.key"
    echo -e "  $0 -c website.crt -i chain.crt -k website.key -p mypassword -a mywebsite -o mywebsite.jks"
    echo -e "  $0 -c website.crt -i chain.crt -k website.key -f PKCS12 -o mywebsite.p12"
    exit 1
}

# ตั้งค่าเริ่มต้น
CERT_FILE=""
CHAIN_FILE=""
KEY_FILE=""
KEYSTORE_PASS="xxxxxxxx"
ALIAS="demo"
KEYSTORE_FORMAT="JKS"  # ค่าเริ่มต้นเป็น JKS
OUTPUT_KEYSTORE=""     # จะกำหนดในภายหลังตาม format
MASKED_PASS=""         # เริ่มต้นค่าว่างเปล่า

# รับค่าพารามิเตอร์
while getopts "c:i:k:p:a:o:f:" opt; do
    case $opt in
        c) CERT_FILE="$OPTARG" ;;
        i) CHAIN_FILE="$OPTARG" ;;
        k) KEY_FILE="$OPTARG" ;;
        p) KEYSTORE_PASS="$OPTARG" ;;
        a) ALIAS="$OPTARG" ;;
        o) OUTPUT_KEYSTORE="$OPTARG" ;;
        f) KEYSTORE_FORMAT=$(echo "$OPTARG" | tr '[:lower:]' '[:upper:]') ;;
        *) usage ;;
    esac
done

# ตรวจสอบว่า format ถูกต้อง
if [[ "$KEYSTORE_FORMAT" != "JKS" && "$KEYSTORE_FORMAT" != "PKCS12" ]]; then
    echo -e "${RED}❌ Error: รูปแบบ keystore ไม่ถูกต้อง ต้องเป็น JKS หรือ PKCS12 เท่านั้น${NC}"
    exit 1
fi

# กำหนดค่า output filename ถ้ายังไม่ได้ระบุ
if [[ -z "$OUTPUT_KEYSTORE" ]]; then
    if [[ "$KEYSTORE_FORMAT" == "JKS" ]]; then
        OUTPUT_KEYSTORE="demo.jks"
    else
        OUTPUT_KEYSTORE="demo.p12"
    fi
fi

# ตรวจสอบค่าพารามิเตอร์จำเป็นถูกระบุครบหรือไม่
if [[ -z "$CERT_FILE" || -z "$CHAIN_FILE" || -z "$KEY_FILE" ]]; then
    echo -e "${RED}❌ Error: กรุณาระบุพารามิเตอร์ให้ครบถ้วน${NC}"
    usage
fi

# ตรวจสอบความยาวของรหัสผ่าน (ต้องมีอย่างน้อย 6 ตัวอักษร)
if [[ ${#KEYSTORE_PASS} -lt 6 ]]; then
    echo -e "${RED}❌ Error: รหัสผ่าน keystore ต้องมีความยาวอย่างน้อย 6 ตัวอักษร${NC}"
    echo -e "${YELLOW}โปรดระบุรหัสผ่านที่ยาวกว่านี้ด้วยพารามิเตอร์ -p${NC}"
    exit 1
fi

# ตรวจสอบว่าไฟล์ input มีอยู่จริง
if [[ ! -f "$CERT_FILE" ]]; then
    echo -e "${RED}❌ Error: ไม่พบไฟล์ certificate: ${YELLOW}$CERT_FILE${NC}"
    exit 1
fi

if [[ ! -f "$CHAIN_FILE" ]]; then
    echo -e "${RED}❌ Error: ไม่พบไฟล์ intermediate chain: ${YELLOW}$CHAIN_FILE${NC}"
    exit 1
fi

if [[ ! -f "$KEY_FILE" ]]; then
    echo -e "${RED}❌ Error: ไม่พบไฟล์ private key: ${YELLOW}$KEY_FILE${NC}"
    exit 1
fi

# สร้าง masked passphrase สำหรับแสดงผล
MASKED_PASS=""
if [[ ${#KEYSTORE_PASS} -gt 0 ]]; then
    # แสดงอักขระแรกและสุดท้าย และแทนที่ตัวอื่นๆ ด้วย *
    if [[ ${#KEYSTORE_PASS} -gt 2 ]]; then
        FIRST_CHAR="${KEYSTORE_PASS:0:1}"
        LAST_CHAR="${KEYSTORE_PASS: -1}"
        MIDDLE_LENGTH=$((${#KEYSTORE_PASS}-2))
        for ((i=0; i<MIDDLE_LENGTH; i++)); do
            MASKED_PASS="${MASKED_PASS}*"
        done
        MASKED_PASS="${FIRST_CHAR}${MASKED_PASS}${LAST_CHAR}"
    else
        # หากรหัสผ่านสั้นเกินไปให้แสดงดาวทั้งหมด
        for ((i=0; i<${#KEYSTORE_PASS}; i++)); do
            MASKED_PASS="${MASKED_PASS}*"
        done
    fi
else
    MASKED_PASS="********"
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║            ${YELLOW}เริ่มต้นกระบวนการสร้าง $KEYSTORE_FORMAT Keystore${BLUE}                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# สร้างไฟล์ชั่วคราว
TEMP_DIR=$(mktemp -d)
PKCS12_FILE="$TEMP_DIR/keystore.p12"
COMBINED_CERT="$TEMP_DIR/combined.crt"

# รวม certificate และ chain เข้าด้วยกัน
echo -e "${CYAN}[1/4]${NC} กำลังรวม certificate และ certificate chain..."
cat "$CERT_FILE" "$CHAIN_FILE" > "$COMBINED_CERT"
echo -e "      ${GREEN}✅ รวมไฟล์เรียบร้อย${NC}"

# แปลง private key และ certificate เป็น PKCS12 format
echo -e "${CYAN}[2/4]${NC} กำลังแปลงเป็น PKCS12 format..."
openssl pkcs12 -export -in "$COMBINED_CERT" -inkey "$KEY_FILE" \
    -out "$PKCS12_FILE" -name "$ALIAS" -passout "pass:$KEYSTORE_PASS"

if [[ $? -ne 0 ]]; then
    echo -e "${RED}❌ Error: ไม่สามารถสร้างไฟล์ PKCS12 ได้${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi
echo -e "      ${GREEN}✅ แปลงเป็น PKCS12 เรียบร้อย${NC}"

# ถ้าเลือก format เป็น PKCS12 ก็ใช้ไฟล์ PKCS12 โดยตรง
if [[ "$KEYSTORE_FORMAT" == "PKCS12" ]]; then
    echo -e "${CYAN}[3/4]${NC} กำลังใช้ PKCS12 format ตามที่ระบุ..."
    cp "$PKCS12_FILE" "$OUTPUT_KEYSTORE"
    
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Error: ไม่สามารถคัดลอกไฟล์ PKCS12 ได้${NC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    echo -e "      ${GREEN}✅ สร้างไฟล์ PKCS12 เรียบร้อย${NC}"
else
    # แปลง PKCS12 เป็น JKS format (กรณีเลือก JKS)
    echo -e "${CYAN}[3/4]${NC} กำลังแปลง PKCS12 เป็น JKS format..."
    keytool -importkeystore -srckeystore "$PKCS12_FILE" -srcstoretype PKCS12 \
        -srcstorepass "$KEYSTORE_PASS" -destkeystore "$OUTPUT_KEYSTORE" \
        -deststoretype JKS -deststorepass "$KEYSTORE_PASS"

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}❌ Error: ไม่สามารถแปลงเป็น JKS format ได้${NC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    echo -e "      ${GREEN}✅ แปลงเป็น JKS เรียบร้อย${NC}"
fi

# ลบไฟล์ชั่วคราว
echo -e "${CYAN}[4/4]${NC} กำลังทำความสะอาดไฟล์ชั่วคราว..."
rm -rf "$TEMP_DIR"
echo -e "      ${GREEN}✅ ทำความสะอาดเรียบร้อย${NC}"

echo ""
echo -e "${GREEN}✅ การสร้าง $KEYSTORE_FORMAT Keystore สำเร็จ:${NC} ${YELLOW}$OUTPUT_KEYSTORE${NC}"
echo ""
# แสดงรายละเอียด keystore ในรูปแบบที่สวยงาม
echo -e "${PURPLE}┌────────────────────── รายละเอียด Keystore ───────────────────────┐${NC}"

# ดึงข้อมูล keystore แบบครบถ้วนโดยไม่ใช้ pipe และซ่อน warning
KEYSTORE_INFO=$(keytool -list -v -keystore "$OUTPUT_KEYSTORE" -storepass "$KEYSTORE_PASS" -storetype "$KEYSTORE_FORMAT" 2>&1 | grep -v "Warning:" | grep -v "proprietary format" | grep -v "migrate to PKCS12")

# แสดงประเภท keystore
STORE_TYPE=$(echo "$KEYSTORE_INFO" | grep "Keystore type:" | head -1)
if [[ -n "$STORE_TYPE" ]]; then
    echo -e "${PURPLE}│${NC} ${YELLOW}Keystore type:${NC}    $(echo "$STORE_TYPE" | sed 's/Keystore type: //')"
fi

# แสดง provider
PROVIDER=$(echo "$KEYSTORE_INFO" | grep "Keystore provider:" | head -1)
if [[ -n "$PROVIDER" ]]; then
    echo -e "${PURPLE}│${NC} ${YELLOW}Keystore provider:${NC} $(echo "$PROVIDER" | sed 's/Keystore provider: //')"
fi

# จำนวน entries
ENTRY_COUNT=$(echo "$KEYSTORE_INFO" | grep "Your keystore contains" | head -1)
if [[ -n "$ENTRY_COUNT" ]]; then
    ENTRIES=$(echo "$ENTRY_COUNT" | sed 's/Your keystore contains //' | sed 's/ entries.//')
    echo -e "${PURPLE}│${NC} ${YELLOW}Entries in keystore:${NC} $ENTRIES"
fi

# เริ่มแสดงรายละเอียด certificates
echo -e "${PURPLE}│${NC}"
echo -e "${PURPLE}│${NC} ${CYAN}Certificate entries:${NC}"

# ตรวจสอบว่ามี alias หรือไม่
ALIASES=$(echo "$KEYSTORE_INFO" | grep "Alias name:" | sed 's/Alias name: //')
if [[ -n "$ALIASES" ]]; then
    # มี alias อย่างน้อย 1 อัน ให้แสดงรายละเอียด
    echo "$KEYSTORE_INFO" | awk '
    BEGIN { print_line=0; entry_count=0; }
    /Alias name:/ { 
        print_line=1; 
        entry_count++; 
        if (entry_count > 1) printf "\n"; 
        printf "'"${PURPLE}│${NC} ${GREEN}--------------------------------------------${NC}"'\n"; 
        printf "'"${PURPLE}│${NC} ${YELLOW}Alias:${NC}          "'" "%s\n", $3; 
        next; 
    }
    /Creation date:/ { 
        if (print_line) printf "'"${PURPLE}│${NC} ${YELLOW}Creation date:${NC}   "'" "%s %s %s\n", $3, $4, $5; 
        next; 
    }
    /Entry type:/ { 
        if (print_line) printf "'"${PURPLE}│${NC} ${YELLOW}Entry type:${NC}      "'" "%s\n", $3; 
        next; 
    }
    /Owner:/ { 
        if (print_line) {
            sub(/Owner: /, "");
            if (length($0) > 50)
                printf "'"${PURPLE}│${NC} ${YELLOW}Owner:${NC}           "'" "%.50s...\n", $0;
            else
                printf "'"${PURPLE}│${NC} ${YELLOW}Owner:${NC}           "'" "%s\n", $0;
        }
        next; 
    }
    /Issuer:/ { 
        if (print_line) {
            sub(/Issuer: /, "");
            if (length($0) > 50)
                printf "'"${PURPLE}│${NC} ${YELLOW}Issuer:${NC}          "'" "%.50s...\n", $0;
            else
                printf "'"${PURPLE}│${NC} ${YELLOW}Issuer:${NC}          "'" "%s\n", $0;
        }
        next; 
    }
    /Serial number:/ { 
        if (print_line) {
            sub(/Serial number: /, "");
            printf "'"${PURPLE}│${NC} ${YELLOW}Serial number:${NC}   "'" "%s\n", $0;
        }
        next; 
    }
    /Valid from:/ { 
        if (print_line) {
            sub(/Valid from: /, "");
            printf "'"${PURPLE}│${NC} ${YELLOW}Valid from:${NC}      "'" "%s\n", $0;
        }
        next; 
    }
    /Valid until:/ { 
        if (print_line) {
            sub(/Valid until: /, "");
            printf "'"${PURPLE}│${NC} ${YELLOW}Valid until:${NC}     "'" "%s\n", $0;
        }
        next; 
    }
    /Certificate fingerprints:/ { 
        if (print_line) printf "'"${PURPLE}│${NC} ${YELLOW}Fingerprints:${NC}"'\n"; 
        next; 
    }
    /SHA1:/ { 
        if (print_line) {
            sub(/\s*SHA1: /, "");
            printf "'"${PURPLE}│${NC}   ${CYAN}SHA1:${NC}  "'" "%s\n", $0;
        }
        next; 
    }
    /SHA256:/ { 
        if (print_line) {
            sub(/\s*SHA256: /, "");
            printf "'"${PURPLE}│${NC}   ${CYAN}SHA256:${NC} "'" "%s\n", $0;
        }
        next; 
    }
    /Signature algorithm name:/ { 
        if (print_line) printf "'"${PURPLE}│${NC} ${YELLOW}Signature algo:${NC}  "'" "%s\n", $4; 
        next; 
    }
    /Version:/ { 
        if (print_line) printf "'"${PURPLE}│${NC} ${YELLOW}Version:${NC}         "'" "%s\n", $2; 
        next; 
    }
    '
else
    # ไม่พบ alias ใดๆ
    echo -e "${PURPLE}│${NC} ${YELLOW}ไม่พบข้อมูล certificate${NC}"
fi

echo -e "${PURPLE}└────────────────────────────────────────────────────────────────┘${NC}"

echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║                  วิธีใช้งานกับ Tomcat                              ║${NC}"
echo -e "${YELLOW}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}1.${NC} คัดลอกไฟล์ ${GREEN}$OUTPUT_KEYSTORE${NC} ไปยังโฟลเดอร์ที่ต้องการ (เช่น /etc/tomcat/ssl/)"
echo -e "${CYAN}2.${NC} แก้ไขไฟล์ ${GREEN}server.xml${NC} ของ Tomcat โดยเพิ่ม connector ดังนี้:"
echo ""
echo -e "${BLUE}┌───────────────── Tomcat Configuration Example ─────────────────┐${NC}"
echo -e "${BLUE}│${NC}"
echo -e "${BLUE}│${NC} ${GREEN}<Connector${NC} ${YELLOW}port${NC}=${CYAN}\"8443\"${NC} ${YELLOW}protocol${NC}=${CYAN}\"org.apache.coyote.http11.Http11NioProtocol\"${NC}"
echo -e "${BLUE}│${NC}            ${YELLOW}maxThreads${NC}=${CYAN}\"150\"${NC} ${YELLOW}SSLEnabled${NC}=${CYAN}\"true\"${NC}${GREEN}>${NC}"
echo -e "${BLUE}│${NC}     ${GREEN}<SSLHostConfig>${NC}"
echo -e "${BLUE}│${NC}         ${GREEN}<Certificate${NC} ${YELLOW}certificateKeystoreFile${NC}=${CYAN}\"/path/to/$OUTPUT_KEYSTORE\"${NC}"
echo -e "${BLUE}│${NC}                      ${YELLOW}certificateKeystorePassword${NC}=${CYAN}\"$MASKED_PASS\"${NC}"
if [[ "$KEYSTORE_FORMAT" == "PKCS12" ]]; then
echo -e "${BLUE}│${NC}                      ${YELLOW}certificateKeystoreType${NC}=${CYAN}\"PKCS12\"${NC}"
fi
echo -e "${BLUE}│${NC}                      ${YELLOW}type${NC}=${CYAN}\"RSA\"${NC} ${GREEN}/>${NC}"
echo -e "${BLUE}│${NC}     ${GREEN}</SSLHostConfig>${NC}"
echo -e "${BLUE}│${NC} ${GREEN}</Connector>${NC}"
echo -e "${BLUE}│${NC}"
echo -e "${BLUE}└────────────────────────────────────────────────────────────────┘${NC}"
echo ""

# แสดงข้อมูลเพิ่มเติมสำหรับ Tomcat รุ่นต่างๆ
if [[ "$KEYSTORE_FORMAT" == "PKCS12" ]]; then
    echo -e "${YELLOW}ข้อมูลเพิ่มเติม:${NC}"
    echo -e "${CYAN}•${NC} รูปแบบ ${GREEN}PKCS12${NC} เป็นมาตรฐานอุตสาหกรรมที่แนะนำให้ใช้แทน JKS"
    echo -e "${CYAN}•${NC} Tomcat รองรับ PKCS12 ตั้งแต่เวอร์ชัน 8.5 เป็นต้นไป"
    echo -e "${CYAN}•${NC} ตั้งแต่ Java 9 เป็นต้นไป PKCS12 ได้กลายเป็นรูปแบบมาตรฐานสำหรับ keystore"
    echo ""
fi

echo -e "${CYAN}3.${NC} รีสตาร์ท Tomcat เพื่อให้การเปลี่ยนแปลงมีผล"
echo ""
echo -e "${YELLOW}การดำเนินการเสร็จสิ้น ${GREEN}✨${NC}\n"