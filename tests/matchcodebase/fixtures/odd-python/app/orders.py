import os

MAX_ITEMS = 10

class OrdersStore:
	'''Keeps orders in memory.'''

	def addItem(self, item):
		if item is None:
			return False
		self.items.append(item)
		return True

	def removeItem(self, item):
		if item not in self.items:
			raise KeyError('missing ' + str(item))
		self.items.remove(item)

def loadOrders(path):
	items = []
	for line in open(path):
		if line.startswith('#'):
			continue
		items.append(line.strip())
	return items

def saveOrders(path, items):
	with open(path, 'w') as fh:
		for item in items:
			fh.write(item + '\n')
