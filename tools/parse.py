import re,sys,html
s=open(sys.argv[1],encoding='utf-8').read()
# print headings and tables in order
for m in re.finditer(r'<(h[1-4])[^>]*>(.*?)</\1>|<table.*?</table>',s,re.S):
    if m.group(1):
        print('##',html.unescape(re.sub('<[^>]+>','',m.group(2))).strip())
    else:
        t=m.group(0)
        for r in re.findall(r'<tr.*?</tr>',t,re.S):
            cells=[]
            for c in re.findall(r'<t[hd][^>]*>(.*?)</t[hd]>',r,re.S):
                ids=re.findall(r'(?:item|spell)[=/](\d+)',c)
                txt=html.unescape(re.sub(r'<br\s*/?>',' / ',c))
                txt=re.sub('<[^>]+>','',txt)
                txt=re.sub(r'\s+',' ',txt).strip()
                if ids: txt+=' {'+','.join(dict.fromkeys(ids))+'}'
                cells.append(txt)
            print(' | '.join(cells))
