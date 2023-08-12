__desciption__="This is template of make function show version and dependency "
__help__="help messages "
__contributors__ = "Randy, "
__last_contributor__="Randy "
__version__ = "1.0.0" #Module name _ branch _ version _ datecode
					  #exsample: WASSI9Autostart_B_0.0.19_20220726

###dependency list report
import requests
import importlib_metadata
get_version=importlib_metadata.version   # don't use from xx import xx as xx, 
		#the libaray would not show on dependency list
def list_dependency():

	modules = []
	for module in globals().items():
		#print(module)
		if("module" in str(type(module[1]))) and  not("__" in module[0]):
			print(module[0]+": ",end='')
			try:
				print(get_version(module[0]))
			except:
				print ("Version not found")
###


if __name__ == '__main__':
	print("-----File Version-----")
	print(__desciption__)
	print(__help__)
	print(__contributors__)
	print(__last_contributor__)
	print(__version__)
	print("-----Dependency-----")
	list_dependency()