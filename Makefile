M80PATH=D:/M80

.SUFFIXES: .ASM .REL .BIN

.ASM.REL:
	M80 '=$< /I/L'

clean:
	del *.REL
	del *.PRN
	del *.BIN

all: Get.COM


Get.COM: Get.REL
	$(M80PATH)/L80 /P:100,$<,$@/N/E

