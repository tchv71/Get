M80PATH=D:/M80

.SUFFIXES: .ASM .REL .BIN

.ASM.REL:
	M80 '=$< /I/L'

clean:
	del *.REL
	del *.PRN
	del *.BIN

all: Get.RKL G1.rkl


Get.COM: Get.REL
	$(M80PATH)/L80 /P:100,$<,$@/N/E

Get.RKL: Get.COM
	../makerk/Release/makerk.exe 100 $< $@

G1.COM: G1.REL
	$(M80PATH)/L80 /P:100,$<,$@/N/E

G1.RKL: G1.COM
	../makerk/Release/makerk.exe 100 $< $@
