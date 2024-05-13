from mitmproxy import ctx

def request(flow):
    print(flow.request.url)
    ctx.master.shutdown()
