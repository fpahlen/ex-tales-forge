def face(mood='neutral', hair='#3a2a1c', skin='#d9b48f', bg='#3a4a5c', size=120, female=False, beard=False, old=False, hood=False):
    brows={'wary':'M38 50 L52 54 M68 54 L82 50','curious':'M38 52 L52 50 M68 46 L82 44',
           'hostile':'M38 47 L54 55 M66 55 L82 47','nervous':'M38 52 L52 47 M68 47 L82 52','neutral':'M38 51 L52 51 M68 51 L82 51','warm':'M38 50 Q45 46 52 49 M68 49 Q75 46 82 50'}[mood]
    mouth={'wary':'M50 84 L70 84','curious':'M50 84 Q60 89 70 83','hostile':'M49 87 Q60 80 71 87','nervous':'M49 85 Q54 82 59 85 Q64 88 70 84','neutral':'M51 84 L69 84','warm':'M48 82 Q60 92 72 82'}[mood]
    h=''
    if female: h=f'<path d="M30 60 Q28 20 60 18 Q92 20 90 60 L94 104 Q84 88 86 60 Q80 34 60 34 Q40 34 34 60 Q36 88 26 104 Z" fill="{hair}"/>'
    else: h=f'<path d="M33 52 Q32 22 60 20 Q88 22 87 52 Q80 34 60 34 Q40 34 33 52Z" fill="{hair}"/>'
    if hood: h=f'<path d="M22 110 Q18 30 60 14 Q102 30 98 110 L86 110 Q90 44 60 32 Q30 44 34 110Z" fill="{hair}"/>'
    b=f'<path d="M38 74 Q40 104 60 106 Q80 104 82 74 Q76 92 60 94 Q44 92 38 74Z" fill="{hair}" opacity=".9"/>' if beard else ''
    lines='<path d="M42 62 L48 61 M72 61 L78 62" stroke="#2a1d12" stroke-width="1" opacity=".5"/><path d="M44 96 Q60 100 76 96" stroke="#2a1d12" stroke-width="1" fill="none" opacity=".4"/>' if old else ''
    return f'''<svg width="{size}" height="{size}" viewBox="0 0 120 120"><rect width="120" height="120" fill="{bg}"/>
<path d="M14 120 Q20 100 60 98 Q100 100 106 120Z" fill="#2b2620"/>
<ellipse cx="60" cy="64" rx="25" ry="31" fill="{skin}"/>{h}{b}{lines}
<path d="{brows}" stroke="#2a1d12" stroke-width="2.6" stroke-linecap="round" fill="none"/>
<circle cx="46" cy="61" r="2.6" fill="#1d140c"/><circle cx="74" cy="61" r="2.6" fill="#1d140c"/>
<path d="M60 64 L57 76 L62 77" stroke="#7a5638" stroke-width="1.6" fill="none"/>
<path d="{mouth}" stroke="#5a2a1c" stroke-width="2.4" stroke-linecap="round" fill="none"/></svg>'''
